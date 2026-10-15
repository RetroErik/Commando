#nullable enable
// Offline register extraction from a PSID file.
// By Dag Erik Hagesæter / Retro Erik using Codex in VS Code
// This executes legal 6502 instructions, but does not synthesize SID audio.
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

sealed class Cpu6502
{
    const int Carry = 1, Zero = 2, Interrupt = 4, Decimal = 8, Overflow = 64, Negative = 128;
    public readonly byte[] Mem = new byte[65536];
    public byte A, X, Y, S = 0xFD, P = Interrupt | 32;
    public ushort PC;
    public uint SidWrites;

    byte Read(int address) => Mem[(ushort)address];
    void Write(int address, int value)
    {
        address = (ushort)address;
        Mem[address] = (byte)value;
        if (address >= 0xD400 && address <= 0xD418) SidWrites++;
    }
    byte Fetch() { byte v = Read(PC); PC++; return v; }
    ushort Word() { int lo = Fetch(); return (ushort)(lo | (Fetch() << 8)); }
    void Push(int v) { Write(0x100 | S, v); S--; }
    byte Pop() { S++; return Read(0x100 | S); }
    void SetNZ(int v) => P = (byte)((P & ~(Negative | Zero)) | (v & Negative) | (((byte)v == 0) ? Zero : 0));
    void Compare(int left, int right)
    {
        int diff = (byte)(left - right);
        P = (byte)((P & ~(Carry | Negative | Zero)) | (left >= right ? Carry : 0) |
                   (diff & Negative) | (diff == 0 ? Zero : 0));
    }
    void Adc(int value)
    {
        int sum = A + value + (P & Carry), result = sum & 255;
        P = (byte)((P & ~(Carry | Overflow)) | (sum > 255 ? Carry : 0) |
                   (((~(A ^ value) & (A ^ result) & 128) != 0) ? Overflow : 0));
        A = (byte)result; SetNZ(A);
    }
    ushort Group1Address(int mode)
    {
        int zp, lo;
        switch (mode)
        {
            case 0: zp = (byte)(Fetch() + X); return (ushort)(Read(zp) | (Read((byte)(zp + 1)) << 8));
            case 1: return Fetch();
            case 2: return PC++;
            case 3: return Word();
            case 4: zp = Fetch(); lo = Read(zp) | (Read((byte)(zp + 1)) << 8); return (ushort)(lo + Y);
            case 5: return (byte)(Fetch() + X);
            case 6: return (ushort)(Word() + Y);
            default: return (ushort)(Word() + X);
        }
    }
    public void Call(ushort address, byte tune)
    {
        A = tune; X = 0; Y = 0; PC = address;
        Push(0xFF); Push(0xFF);
        for (int i = 0; i < 200000; i++)
        {
            if (PC == 0) return;
            Step();
        }
        throw new Exception($"6502 call at ${address:X4} exceeded instruction limit (PC ${PC:X4}).");
    }
    void Step()
    {
        ushort at = PC;
        int op = Fetch(), kind = op >> 5, mode = (op >> 2) & 7, a, v;
        if ((op & 3) == 1 && !(kind == 4 && mode == 2))
        {
            a = Group1Address(mode); v = Read(a);
            switch (kind)
            {
                case 0: A |= (byte)v; SetNZ(A); break;
                case 1: A &= (byte)v; SetNZ(A); break;
                case 2: A ^= (byte)v; SetNZ(A); break;
                case 3: Adc(v); break;
                case 4: Write(a, A); break;
                case 5: A = (byte)v; SetNZ(A); break;
                case 6: Compare(A, v); break;
                case 7: Adc(v ^ 255); break;
            }
            return;
        }
        bool group2 = (op & 3) == 2 &&
            (kind <= 3 ? mode is 1 or 2 or 3 or 5 or 7 :
             kind == 4 ? mode is 1 or 3 or 5 :
             kind == 5 ? mode is 0 or 1 or 3 or 5 or 7 :
             mode is 1 or 3 or 5 or 7);
        if (group2)
        {
            if (mode == 0) { X = Fetch(); SetNZ(X); return; }
            if (mode == 2) { a = 0; v = A; }
            else
            {
                a = mode switch
                {
                    1 => Fetch(),
                    3 => Word(),
                    5 => (byte)(Fetch() + ((kind == 4 || kind == 5) ? Y : X)),
                    7 => (ushort)(Word() + (kind == 5 ? Y : X)),
                    _ => throw new InvalidOperationException()
                };
                v = Read(a);
            }
            switch (kind)
            {
                case 0: P = (byte)((P & ~Carry) | (v >> 7)); v = (byte)(v << 1); SetNZ(v); break;
                case 1: { int carry = P & Carry; P = (byte)((P & ~Carry) | (v >> 7)); v = (byte)((v << 1) | carry); SetNZ(v); break; }
                case 2: P = (byte)((P & ~Carry) | (v & Carry)); v >>= 1; SetNZ(v); break;
                case 3: { int carry = P & Carry; P = (byte)((P & ~Carry) | (v & Carry)); v = (v >> 1) | (carry << 7); SetNZ(v); break; }
                case 4: Write(a, X); return;
                case 5: X = (byte)v; SetNZ(X); return;
                case 6: v = (byte)(v - 1); SetNZ(v); break;
                case 7: v = (byte)(v + 1); SetNZ(v); break;
            }
            if (mode == 2) A = (byte)v; else Write(a, v);
            return;
        }
        if ((op & 0x1F) == 0x10)
        {
            bool condition = (op >> 6) switch
            {
                0 => (P & Negative) != 0,
                1 => (P & Overflow) != 0,
                2 => (P & Carry) != 0,
                _ => (P & Zero) != 0
            };
            bool taken = ((op & 0x20) != 0) == condition;
            sbyte delta = (sbyte)Fetch();
            if (taken) PC = (ushort)(PC + delta);
            return;
        }
        switch (op)
        {
            case 0x00: throw new Exception($"BRK at ${at:X4}");
            case 0x08: Push(P | 48); break;
            case 0x18: P &= unchecked((byte)~Carry); break;
            case 0x20: a = Word(); Push((PC - 1) >> 8); Push(PC - 1); PC = (ushort)a; break;
            case 0x24: case 0x2C:
                a = op == 0x24 ? Fetch() : Word(); v = Read(a);
                P = (byte)((P & ~(Negative | Overflow | Zero)) | (v & (Negative | Overflow)) | ((v & A) == 0 ? Zero : 0)); break;
            case 0x28: P = (byte)(Pop() | 32); break;
            case 0x38: P |= Carry; break;
            case 0x40: P = Pop(); v = Pop(); PC = (ushort)(v | (Pop() << 8)); break;
            case 0x48: Push(A); break;
            case 0x4C: PC = Word(); break;
            case 0x58: P &= unchecked((byte)~Interrupt); break;
            case 0x60: v = Pop(); PC = (ushort)((v | (Pop() << 8)) + 1); break;
            case 0x68: A = Pop(); SetNZ(A); break;
            case 0x6C:
                a = Word(); PC = (ushort)(Read(a) | (Read((a & 0xFF00) | ((a + 1) & 255)) << 8)); break;
            case 0x78: P |= Interrupt; break;
            case 0x84: case 0x94: case 0x8C:
                a = op == 0x8C ? Word() : Fetch(); if (op == 0x94) a = (byte)(a + X); Write(a, Y); break;
            case 0x88: Y--; SetNZ(Y); break;
            case 0x8A: A = X; SetNZ(A); break;
            case 0x98: A = Y; SetNZ(A); break;
            case 0x9A: S = X; break;
            case 0xA0: case 0xA4: case 0xB4: case 0xAC: case 0xBC:
                if (op == 0xA0) v = Fetch();
                else { a = op is 0xAC or 0xBC ? Word() : Fetch(); if (op == 0xB4) a = (byte)(a + X); if (op == 0xBC) a = (ushort)(a + X); v = Read(a); }
                Y = (byte)v; SetNZ(Y); break;
            case 0xA8: Y = A; SetNZ(Y); break;
            case 0xAA: X = A; SetNZ(X); break;
            case 0xB8: P &= unchecked((byte)~Overflow); break;
            case 0xBA: X = S; SetNZ(X); break;
            case 0xC0: case 0xC4: case 0xCC: v = op == 0xC0 ? Fetch() : Read(op == 0xC4 ? Fetch() : Word()); Compare(Y, v); break;
            case 0xC8: Y++; SetNZ(Y); break;
            case 0xCA: X--; SetNZ(X); break;
            case 0xD8: P &= unchecked((byte)~Decimal); break;
            case 0xE0: case 0xE4: case 0xEC: v = op == 0xE0 ? Fetch() : Read(op == 0xE4 ? Fetch() : Word()); Compare(X, v); break;
            case 0xE8: X++; SetNZ(X); break;
            case 0xEA: break;
            case 0xF8: P |= Decimal; break;
            default: throw new Exception($"Unsupported 6502 opcode ${op:X2} at ${at:X4}");
        }
    }
}

public static class Program
{
    static ushort Be16(byte[] b, int at) => (ushort)((b[at] << 8) | b[at + 1]);
    // Datasheet attack and decay/release times, in milliseconds at 1 MHz.
    static readonly double[] AttackMs = { 2, 8, 16, 24, 38, 56, 68, 80, 100, 250, 500, 800, 1000, 3000, 5000, 8000 };
    static readonly double[] FallMs = { 6, 24, 48, 72, 114, 168, 204, 240, 300, 750, 1500, 2400, 3000, 9000, 15000, 24000 };

    sealed class Envelope
    {
        enum Stage { Attack, Decay, Release }
        Stage stage = Stage.Release;
        bool previousGate;
        double level;

        public int Advance(bool gate, byte attackDecay, byte sustainRelease)
        {
            if (gate && !previousGate) stage = Stage.Attack;
            if (!gate && previousGate) stage = Stage.Release;
            previousGate = gate;
            if (stage == Stage.Attack)
            {
                level += 255.0 * 20.0 / AttackMs[attackDecay >> 4];
                if (level >= 255.0) { level = 255.0; stage = Stage.Decay; }
            }
            else
            {
                double target = stage == Stage.Decay ? (sustainRelease >> 4) * 17.0 : 0.0;
                double duration = FallMs[stage == Stage.Decay ? attackDecay & 15 : sustainRelease & 15];
                level = target + (level - target) * Math.Exp(-4.6 * 20.0 / duration);
            }
            level = Math.Clamp(level, 0.0, 255.0);
            return (int)Math.Round(level * 7.0 / 255.0);
        }
    }

    static void MapCmsVoice(byte[] sid, int voice, out byte tone, out byte state)
    {
        int b = 0xD400 + 7 * voice;
        int control = sid[b + 4];
        bool gate = (control & 1) != 0 && (control & 0xF0) != 0;
        if (!gate) { tone = 0; state = 0; return; }
        int sidFrequency = sid[b] | (sid[b + 1] << 8);
        double hz = sidFrequency * 985248.0 / 16777216.0;
        int octave = 0;
        while (hz > 122.0 && octave < 7) { hz /= 2.0; octave++; }
        hz = Math.Clamp(hz, 61.0, 122.0);
        tone = (byte)Math.Clamp(511 - (int)Math.Round(31250.0 / hz), 0, 255);
        state = (byte)(0x80 | ((control & 0x80) != 0 ? 0x40 : 0) | octave);
    }
    static void MapCmsEnvelopeVoice(byte[] sid, int voice, Envelope envelope, out byte tone, out byte state)
    {
        int b = 0xD400 + 7 * voice;
        int control = sid[b + 4];
        bool gate = (control & 1) != 0 && (control & 0xF0) != 0;
        int volume = envelope.Advance(gate, sid[b + 5], sid[b + 6]);
        if (volume == 0 || (control & 0xF0) == 0) { tone = 0; state = 0; return; }
        int sidFrequency = sid[b] | (sid[b + 1] << 8);
        double hz = sidFrequency * 985248.0 / 16777216.0;
        int octave = 0;
        while (hz > 122.0 && octave < 7) { hz /= 2.0; octave++; }
        hz = Math.Clamp(hz, 61.0, 122.0);
        tone = (byte)Math.Clamp(511 - (int)Math.Round(31250.0 / hz), 0, 255);
        state = (byte)(0x80 | ((control & 0x80) != 0 ? 0x40 : 0) | (volume << 3) | octave);
    }
    static void FlushSilence(List<byte> score, ref int silence)
    {
        while (silence > 0)
        {
            // 0xFF is reserved for the score loop marker.
            int span = Math.Min(silence, 126);
            score.Add((byte)(0x80 | span));
            silence -= span;
        }
    }
    public static int Main(string[] args)
    {
        bool envelopeMode = args.Length == 5 && args[4] == "--cms-envelope";
        bool cmsMode = args.Length == 5 && (args[4] == "--cms" || envelopeMode);
        if ((args.Length != 3 && args.Length != 4 && !cmsMode) || !int.TryParse(args[1], out int tune) || !int.TryParse(args[2], out int frames))
        {
            Console.Error.WriteLine("Usage: SidDump SID_FILE SUBTUNE FRAMES [OUTPUT [--cms|--cms-envelope]]"); return 2;
        }
        byte[] sid = File.ReadAllBytes(args[0]);
        if (sid.Length < 126 || Encoding.ASCII.GetString(sid, 0, 4) != "PSID") throw new Exception("Expected PSID file.");
        int data = Be16(sid, 6), load = Be16(sid, 8), init = Be16(sid, 10), play = Be16(sid, 12), songs = Be16(sid, 14);
        if (tune < 1 || tune > songs || frames < 1 || frames > 30000) throw new Exception("Invalid tune or frame count.");
        if (load == 0) { load = sid[data] | (sid[data + 1] << 8); data += 2; }
        if (load + sid.Length - data > 65536) throw new Exception("SID payload exceeds C64 memory.");
        Cpu6502 cpu = new();
        Array.Copy(sid, data, cpu.Mem, load, sid.Length - data);
        cpu.Call((ushort)init, (byte)(tune - 1));
        Console.Error.WriteLine($"Loaded ${load:X4}; init ${init:X4}; play ${play:X4}; tune {tune}; init SID writes {cpu.SidWrites}.");
        if (cmsMode)
        {
            List<byte> score = new();
            byte[] lastTone = new byte[3], lastState = new byte[3];
            Envelope[] envelopes = { new(), new(), new() };
            int silence = 0, changedFrames = 0;
            for (int frame = 0; frame < frames; frame++)
            {
                cpu.Call((ushort)play, (byte)(tune - 1));
                byte[] tones = new byte[3], states = new byte[3];
                int mask = 0;
                for (int voice = 0; voice < 3; voice++)
                {
                    if (envelopeMode) MapCmsEnvelopeVoice(cpu.Mem, voice, envelopes[voice], out tones[voice], out states[voice]);
                    else MapCmsVoice(cpu.Mem, voice, out tones[voice], out states[voice]);
                    if (tones[voice] != lastTone[voice] || states[voice] != lastState[voice]) mask |= 1 << voice;
                }
                if (mask == 0) { silence++; continue; }
                FlushSilence(score, ref silence);
                score.Add((byte)mask);
                for (int voice = 0; voice < 3; voice++)
                {
                    if ((mask & (1 << voice)) == 0) continue;
                    score.Add(tones[voice]); score.Add(states[voice]);
                    lastTone[voice] = tones[voice]; lastState[voice] = states[voice];
                }
                changedFrames++;
            }
            FlushSilence(score, ref silence);
            score.Add(0xFF);
            File.WriteAllBytes(args[3], score.ToArray());
            Console.Error.WriteLine($"CMS score: {frames} frames, {changedFrames} changed frames, {score.Count} bytes.");
            return 0;
        }
        using TextWriter? fileOutput = args.Length == 4 ? new StreamWriter(args[3], false, Encoding.ASCII) : null;
        TextWriter output = fileOutput ?? Console.Out;
        output.Write("frame"); for (int i = 0; i < 25; i++) output.Write($",r{i:X2}"); output.WriteLine();
        for (int frame = 0; frame < frames; frame++)
        {
            cpu.Call((ushort)play, (byte)(tune - 1));
            output.Write(frame);
            for (int i = 0; i < 25; i++) output.Write($",{cpu.Mem[0xD400 + i]:X2}");
            output.WriteLine();
        }
        return 0;
    }
}
