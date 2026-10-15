.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global start

# By Dag Erik Hagesæter / Retro Erik using Codex in VS Code
# Both game-state exit hooks must resume at their original jump targets.
start:
    push cs
    pop ds
    int 0x61
    mov ax, 0xb800
    mov es, ax
    mov byte ptr es:[0x1234], 0x5a
    mov ax, 0xbc00
    mov es, ax
    mov byte ptr es:[0x1234], 0xa5
    int 0x67
    lea dx, [fail_message]
    mov ah, 9
    int 0x21
    mov ax, 0x4c01
    int 0x21

    .org 0x328c
play_landing:
    mov ax, 0xb800
    mov es, ax
    cmp byte ptr es:[0x1234], 0
    jne failed_exit
    mov ax, 0xbc00
    mov es, ax
    cmp byte ptr es:[0x1234], 0
    jne failed_exit
    lea dx, [pass_message]
    mov ah, 9
    int 0x21
    mov ax, 0x4c00
    int 0x21

    .org 0x32c8
attract_landing:
    mov ax, 0xb800
    mov es, ax
    cmp byte ptr es:[0x1234], 0
    jne failed_exit
    mov byte ptr es:[0x1234], 0x5a
    mov ax, 0xbc00
    mov es, ax
    cmp byte ptr es:[0x1234], 0
    jne failed_exit
    mov byte ptr es:[0x1234], 0xa5
    int 0x69
failed_exit:
    lea dx, [fail_message]
    mov ah, 9
    int 0x21
    mov ax, 0x4c01
    int 0x21

pass_message: .ascii "PASS: both state exits clear video and resume at original jump targets.\r\n$"
fail_message: .ascii "FAIL: a game-state exit left video pixels or missed its jump.\r\n$"
