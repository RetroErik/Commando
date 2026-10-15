.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global start

# By Dag Erik Hagesæter / Retro Erik using Codex in VS Code
# Run after the loader returns to DOS to check the PC speaker gate.
start:
    push cs
    pop ds
    in al, 0x61
    test al, 3
    jnz speaker_on
    lea dx, [pass_message]
    mov ah, 9
    int 0x21
    mov ax, 0x4c00
    int 0x21
speaker_on:
    lea dx, [fail_message]
    mov ah, 9
    int 0x21
    mov ax, 0x4c01
    int 0x21

pass_message: .ascii "PASS: speaker off after loader exit.\r\n$"
fail_message: .ascii "FAIL: PC speaker still enabled.\r\n$"
