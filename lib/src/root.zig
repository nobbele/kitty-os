pub const a: u32 = 0xDEADBEEF;

pub fn write(fd: u32, buffer: []const u8) void {
    asm volatile (
        \\ int $0x80
        :
        : [syscall] "{eax}" (1),
          [fd] "{ebx}" (fd),
          [buf] "{ecx}" (buffer.ptr),
          [len] "{edx}" (buffer.len),
    );
}
