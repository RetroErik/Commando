.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global start

# By Dag Erik Hagesæter / Retro Erik using Codex in VS Code
# Verify copied low sprite bytes and the loader's precomputed upper sprites.
start:
    push cs
    pop ds
    push cs
    pop es
    lea sp, [test_stack_top]
    lea bx, [test_stack_top + 15]
    shr bx, 1
    shr bx, 1
    shr bx, 1
    shr bx, 1
    mov ah, 0x4a
    int 0x21
    jc fail1
    cmp byte ptr [enemy_sprite + 17], 0
    jne fail1
    cmp byte ptr [enemy_sprite + 119], 0x3c
    jne fail1
    cmp byte ptr [hero_sprite + 17], 0xa8
    jne fail1
    cmp byte ptr [hero_sprite + 119], 0
    jne fail1

    int 0x61
    mov word ptr [0xf8fc], offset object_record
    mov word ptr [0xf8fe], 4
    mov ah, 0x48
    mov bx, 0x400
    int 0x21
    jc fail2
    mov word ptr [screen_segment], ax
    mov es, ax
    xor ax, ax
    push ax
    push word ptr [screen_segment]
    int 0x63
    add sp, 4
    mov word ptr [0xfe32], 0x1234
    int 0x66
    cmp word ptr [0xfe32], 0
    jne fail3
    mov byte ptr es:[0x201a], 0xa8
    mov byte ptr es:[0x0611], 0x3c
    mov byte ptr es:[0x0002], 0xaa
    mov byte ptr es:[0x0294], 0xff
    mov byte ptr es:[0x028b], 0xff
    mov byte ptr es:[0x02c4], 0xff
    # Horizontal frame bars use rows separate from the score lettering.
    mov byte ptr es:[0x2244], 0xff
    mov byte ptr es:[0x38c4], 0xff
    mov byte ptr es:[0x3f04], 0xff
    mov byte ptr es:[0x1919], 0xff
    mov byte ptr es:[0x1b62], 0xff
    mov byte ptr es:[0x1a7e], 0xff
    mov byte ptr es:[0x1bbe], 0xff
    mov byte ptr es:[0x3c5e], 0xff
    mov byte ptr es:[0x0352], 0xf0
    mov byte ptr es:[0x067c], 0x03
    push word ptr [screen_segment]
    int 0x62
    add sp, 2
    call check_first
    mov byte ptr [stage], 'F'
    mov ax, 0xb800
    mov es, ax
    cmp byte ptr es:[0x0002], 0xff
    jne fail3
    cmp byte ptr es:[0x0294], 0x55
    jne fail3
    cmp byte ptr es:[0x028b], 0x55
    jne fail3
    cmp byte ptr es:[0x02c4], 0x55
    jne fail3
    mov byte ptr [stage], 't'
    cmp byte ptr es:[0x2244], 0x55
    jne fail3
    mov byte ptr [stage], 'u'
    cmp byte ptr es:[0x38c4], 0x55
    jne fail3
    mov byte ptr [stage], 'v'
    cmp byte ptr es:[0x3f04], 0x55
    jne fail3
    mov byte ptr [stage], 'w'
    cmp byte ptr es:[0x1919], 0x55
    jne fail3
    cmp byte ptr es:[0x1b62], 0xff
    jne fail3
    cmp byte ptr es:[0x1a7e], 0xff
    jne fail3
    cmp byte ptr es:[0x1bbe], 0xff
    jne fail3
    cmp byte ptr es:[0x3c5e], 0x55
    jne fail3
    mov ax, 0xbc00
    mov es, ax
    cmp byte ptr es:[0x0002], 0
    jne fail3
    cmp byte ptr es:[0x0294], 0xaa
    jne fail3
    cmp byte ptr es:[0x028b], 0xaa
    jne fail3
    cmp byte ptr es:[0x02c4], 0xaa
    jne fail3
    cmp byte ptr es:[0x2244], 0xaa
    jne fail3
    cmp byte ptr es:[0x38c4], 0xaa
    jne fail3
    cmp byte ptr es:[0x3f04], 0xaa
    jne fail3
    cmp byte ptr es:[0x1919], 0xaa
    jne fail3
    cmp byte ptr es:[0x1b62], 0xff
    jne fail3
    cmp byte ptr es:[0x1a7e], 0
    jne fail3
    cmp byte ptr es:[0x1bbe], 0
    jne fail3
    cmp byte ptr es:[0x3c5e], 0xaa
    jne fail3
    cmp byte ptr es:[0x0352], 0xf0
    jne fail3
    cmp byte ptr es:[0x067c], 0x02
    jne fail3

    # A changing score digit must clear and restore both bank colors.
    mov ax, word ptr [screen_segment]
    mov es, ax
    mov byte ptr es:[0x1919], 0
    push word ptr [screen_segment]
    int 0x62
    add sp, 2
    mov byte ptr [stage], 'G'
    mov ax, 0xbc00
    mov es, ax
    cmp byte ptr es:[0x1919], 0
    jne fail3
    mov ax, word ptr [screen_segment]
    mov es, ax
    mov byte ptr es:[0x1919], 0xff
    push word ptr [screen_segment]
    int 0x62
    add sp, 2
    mov byte ptr [stage], 'H'
    mov ax, 0xb800
    mov es, ax
    cmp byte ptr es:[0x1919], 0x55
    jne fail3
    mov ax, 0xbc00
    mov es, ax
    cmp byte ptr es:[0x1919], 0xaa
    jne fail3

    # Moving the bullet must clear its former upper-bank footprint.
    mov word ptr [object_record + 28], 0x1468
    mov ax, word ptr [screen_segment]
    mov es, ax
    mov byte ptr es:[0x0352], 0
    mov byte ptr es:[0x0354], 0xf0
    push word ptr [screen_segment]
    int 0x62
    add sp, 2
    mov byte ptr [stage], 'J'
    mov ax, 0xbc00
    mov es, ax
    cmp byte ptr es:[0x0352], 0
    jne fail3
    cmp byte ptr es:[0x0354], 0xf0
    jne fail3

    mov word ptr [object_record + 12], 0x1848
    mov byte ptr [stage], 'A'
    mov byte ptr [object_record + 5], 40
    mov ax, word ptr [screen_segment]
    mov es, ax
    mov byte ptr es:[0x0611], 0
    mov byte ptr es:[0x0615], 0x3c
    mov byte ptr es:[0x1000], 0xa8
    push word ptr [screen_segment]
    int 0x62
    add sp, 2
    mov ax, 0xb800
    mov es, ax
    cmp byte ptr es:[0x0000], 0
    jne fail3
    cmp byte ptr es:[0x1000], 0xa8
    jne fail3
    mov ax, 0xbc00
    mov es, ax
    cmp byte ptr es:[0x0000], 0
    jne fail3
    mov dl, 'h'
    cmp byte ptr es:[0x201a], 0
    je hero_old_ok
    mov al, byte ptr es:[0x201a]
    call print_hex
    jmp failed
hero_old_ok:
    mov dl, 'i'
    cmp byte ptr es:[0x265a], 0
    jne failed
    cmp byte ptr es:[0x23e2], 0
    jne fail3
    cmp byte ptr es:[0x23e6], 0xa8
    jne fail3
    cmp byte ptr es:[0x0615], 0x3c
    jne fail3

    mov ax, word ptr [screen_segment]
    mov es, ax
    xor ax, ax
    push ax
    push word ptr [screen_segment]
    int 0x63
    add sp, 4
    mov byte ptr [stage], 'B'
    cmp byte ptr es:[0x1000], 0
    jne fail3
    mov byte ptr es:[0x1000], 0xa8
    mov ax, 0xb800
    mov es, ax
    mov byte ptr es:[0x1000], 0
    push word ptr [screen_segment]
    int 0x62
    add sp, 2
    cmp byte ptr es:[0x1000], 0xa8
    jne fail3
    mov ax, word ptr [screen_segment]
    mov es, ax
    xor ax, ax
    xor di, di
    mov cx, 0x2000
    int 0x64
    mov byte ptr [stage], 'C'
    cmp byte ptr es:[0x1000], 0
    jne fail3
    mov byte ptr es:[0x1000], 0xa8
    mov ax, 0xbc00
    mov es, ax
    cmp byte ptr es:[0x23e6], 0
    jne fail3
    push word ptr [screen_segment]
    int 0x62
    add sp, 2
    mov ax, 0xbc00
    mov es, ax
    cmp byte ptr es:[0x23e6], 0xa8
    jne fail3
    mov ax, word ptr [screen_segment]
    mov es, ax
    xor ax, ax
    push ax
    push word ptr [screen_segment]
    int 0x65
    add sp, 4
    mov byte ptr [stage], 'D'
    cmp byte ptr es:[0x1000], 0
    jne fail3
    mov ax, 0xbc00
    mov es, ax
    cmp byte ptr es:[0x23e6], 0
    jne fail3
    push word ptr [screen_segment]
    int 0x62
    add sp, 2
    cmp byte ptr es:[0x23e6], 0
    jne fail3
    mov ax, word ptr [screen_segment]
    mov es, ax
    int 0x68
    cmp byte ptr [0xfa19], 4
    jne fail3
    mov byte ptr [stage], 'E'
    mov byte ptr es:[0x1000], 0xa8
    push word ptr [screen_segment]
    int 0x62
    add sp, 2
    mov ax, 0xbc00
    mov es, ax
    cmp byte ptr es:[0x23e6], 0xa8
    jne fail3

    # The game's scrolling-ground buffer stays black through a scene clear.
    mov byte ptr [stage], 'P'
    mov ax, word ptr [screen_segment]
    mov es, ax
    xor ax, ax
    push ax
    push word ptr [screen_segment]
    int 0x63
    add sp, 4
    mov byte ptr [stage], 'Q'
    mov al, byte ptr es:[0x097e]
    cmp al, 0
    je black_low_ready
    call print_hex
    jmp fail3
black_low_ready:
    mov byte ptr [stage], 'U'
    cmp byte ptr es:[0x096b], 0
    jne fail3
    mov byte ptr [stage], 'V'
    cmp byte ptr es:[0x2236], 0
    jne fail3
    mov byte ptr [stage], 'W'
    cmp byte ptr es:[0x169e], 0
    jne fail3
    mov byte ptr [object_record + 12], 88
    mov byte ptr [object_record + 13], 32
    mov byte ptr [stage], 'R'
    push word ptr [screen_segment]
    int 0x62
    add sp, 2
    mov ax, 0xb800
    mov es, ax
    mov byte ptr [stage], 'S'
    cmp byte ptr es:[0x097e], 0
    jne fail3
    cmp byte ptr es:[0x096b], 0
    jne fail3
    mov ax, 0xbc00
    mov es, ax
    mov byte ptr [stage], 'T'
    cmp byte ptr es:[0x097e], 0
    jne fail3
    cmp byte ptr es:[0x096b], 0
    jne fail3
    cmp byte ptr es:[0x2236], 0
    jne fail3
    cmp byte ptr es:[0x169e], 0
    jne fail3
    mov byte ptr [stage], 'M'
    cmp byte ptr es:[0x075d], 0x3c
    jne fail3
    mov byte ptr [object_record + 12], 92
    push word ptr [screen_segment]
    int 0x62
    add sp, 2
    cmp byte ptr es:[0x075d], 0
    jne fail3
    cmp byte ptr es:[0x075f], 0x3c
    jne fail3

    mov ax, 3
    int 0x10
    in al, 0x61
    or al, 3
    out 0x61, al
    push cs
    pop ds
    lea dx, [pass_message]
    mov ah, 9
    int 0x21
    mov ax, 0x4c00
    int 0x21

check_first:
    mov ax, 0xb800
    mov es, ax
    mov dl, 'a'
    cmp byte ptr es:[0x201a], 0xa8
    jne failed
    mov dl, 'b'
    cmp byte ptr es:[0x23e2], 0
    jne failed
    mov dl, 'c'
    cmp byte ptr es:[0x0611], 0x3c
    jne failed
    mov ax, 0xbc00
    mov es, ax
    mov dl, 'd'
    cmp byte ptr es:[0x201a], 0
    je hero_high_ok
    mov al, byte ptr es:[0x201a]
    call print_hex
    jmp failed
hero_high_ok:
    mov dl, 'e'
    cmp byte ptr es:[0x23e2], 0xa8
    jne failed
    mov dl, 'f'
    cmp byte ptr es:[0x0609], 0
    jne failed
    mov dl, 'g'
    cmp byte ptr es:[0x0611], 0x3c
    jne failed
    ret

fail1: mov dl, '1'
    jmp failed
fail2: mov dl, '2'
    jmp failed
fail3: mov dl, byte ptr [stage]
failed:
    mov ah, 2
    int 0x21
    mov ax, 3
    int 0x10
    push cs
    pop ds
    lea dx, [fail_message]
    mov ah, 9
    int 0x21
    mov ax, 0x4c01
    int 0x21

print_hex:
    push ax
    shr al, 1
    shr al, 1
    shr al, 1
    shr al, 1
    call print_nibble
    pop ax
    and al, 15
    call print_nibble
    ret
print_nibble:
    cmp al, 10
    jb print_digit
    add al, 7
print_digit:
    add al, '0'
    mov dl, al
    mov ah, 2
    int 0x21
    ret

screen_segment: .word 0
stage: .byte '0'
pass_message: .ascii "PASS: precolored assets, paired copy, black background, play clears, and round exit.\r\n$"
fail_message: .ascii "FAIL: sprite data or video plane differed.\r\n$"
object_record:
    .word hero_sprite, 48, 48, hero_sprite
    .word enemy_sprite, 64, 0x1840, enemy_sprite
    .word rock_sprite, 0x2878, 0x2878, rock_sprite
    .word bullet_sprite, 0x1464, 0x1464, bullet_sprite

    .org 0x1d12
enemy_sprite:
    .incbin "enemy_low.bin"
    .org 0x3cac
hero_sprite:
    .incbin "hero_low.bin"
    .org 0x729a
rock_sprite:
    .incbin "rock_low.bin"
    .org 0x7f4a
bullet_sprite:
    .incbin "effects_low.bin"
    .balign 16
    .space 1024
test_stack_top:
