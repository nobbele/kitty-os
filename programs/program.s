BITS 32

STDOUT equ 1

mov eax, 1
mov ebx, STDOUT
mov ecx, msg
mov edx, msg_len
int 0x80
int3
jmp $

msg: db "Hello, World", 10
msg_len equ $ -msg