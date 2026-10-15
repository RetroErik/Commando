.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global probe_exec

# By Dag Erik Hagesæter / Retro Erik using Codex in VS Code
# Appended only to the copied STARTC0.COM. The original launcher ignores
# EXEC errors and always exits with code zero, hiding startup failures.

probe_exec:
    push cs
    pop es
    int 0x21
    jc probe_failed
    mov ah, 0x4d
    int 0x21
    mov byte ptr cs:[child_code], al
    jmp probe_done
probe_failed:
    or al, 0x80
    mov byte ptr cs:[child_code], al
probe_done:
    cli
    ret

# The original cleanup calls this immediately before DOS termination.
.org 0x30
probe_exit:
    mov al, byte ptr cs:[child_code]
    mov ah, 0x4c
    ret

child_code: .byte 0

# Function 34h gives the DOS busy flag. The copied launcher's INT 13h hook
# must pass DOS's own floppy reads to the original BIOS handler. Otherwise,
# launching the game from A: can substitute COMMANDO.DAT for COMMANDO.EXE.
.org 0x40
probe_install:
    mov ah, 0x34
    int 0x21
    mov word ptr cs:[indos_ptr], bx
    mov word ptr cs:[indos_ptr + 2], es
    mov ax, 0x2513
    mov dx, 0x0248
    int 0x21
    ret

# Replaces the first five bytes of the original INT 13h hook. Its saved
# old-handler far jump remains at 02DBh; normal floppy reads resume at 0250h.
.org 0x70
probe_dispatch:
    push ax
    push bx
    push es
    les bx, dword ptr cs:[indos_ptr]
    mov al, byte ptr es:[bx]
    pop es
    pop bx
    or al, al
    pop ax
    jnz probe_chain
    cmp dl, 0
    jne probe_chain
    jmp word ptr cs:[resume_vector]
probe_chain:
    jmp word ptr cs:[chain_vector]

indos_ptr: .word 0, 0
resume_vector: .word 0x0250
chain_vector: .word 0x02db
