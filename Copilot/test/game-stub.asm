bits 16
cpu 8086
org 100h

    mov ax, 3508h
    int 21h
    mov [old_irq], bx
    mov [old_irq+2], es
    mov dx, fast_irq
    mov ax, 2508h
    int 21h
    cli
    mov al, 36h
    out 43h, al
    mov al, 0aah
    out 40h, al
    mov al, 2ah
    out 40h, al
    sti
    xor ax, ax
    int 1ah
    mov [start_tick], dx
.wait:
    xor ax, ax
    int 1ah
    sub dx, [start_tick]
    cmp dx, 20
    jb .wait
    cli
    mov al, 36h
    out 43h, al
    xor al, al
    out 40h, al
    out 40h, al
    sti
    push ds
    lds dx, [old_irq]
    mov ax, 2508h
    int 21h
    pop ds
    cmp word [irq_count], 110
    jb .fail
    mov ax, 4c07h
    int 21h
.fail:
    mov ax, 4c01h
    int 21h

fast_irq:
    push ax
    inc word [cs:irq_count]
    inc byte [cs:divider]
    cmp byte [cs:divider], 6
    jne .ack
    mov byte [cs:divider], 0
    pushf
    call far [cs:old_irq]
.ack:
    mov al, 20h
    out 20h, al
    pop ax
    iret

old_irq dd 0
start_tick dw 0
irq_count dw 0
divider db 0
