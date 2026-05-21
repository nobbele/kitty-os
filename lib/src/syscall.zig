pub fn read(fd: u32, buffer: []u8) u32 {
    return asm volatile (
        \\ int $0x80
        : [ret] "={eax}" (-> u32),
        : [syscall] "{eax}" (0),
          [fd] "{ebx}" (fd),
          [buf] "{ecx}" (buffer.ptr),
          [len] "{edx}" (buffer.len),
    );
}

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

pub fn exec(path: []const u8) void {
    asm volatile (
        \\ int $0x80
        :
        : [syscall] "{eax}" (2),
          [buf] "{ebx}" (path.ptr),
          [len] "{ecx}" (path.len),
    );
}

pub fn sleep(amount: u32) void {
    asm volatile (
        \\ int $0x80
        :
        : [syscall] "{eax}" (3),
          [amount] "{ebx}" (amount),
    );
}

pub fn yield() void {
    asm volatile (
        \\ int $0x80
        :
        : [syscall] "{eax}" (4),
    );
}

pub fn exit(code: u32) void {
    asm volatile (
        \\ int $0x80
        :
        : [syscall] "{eax}" (5),
          [code] "{ebx}" (code),
    );
}
