BITS 32

mov eax, 1
mov ebx, 0xDEADBEEF
int 0x80
int3
jmp $
