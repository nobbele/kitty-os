const root = @import("root.zig");

pub const Syscall = enum(usize) { read, write, exec, sleep, yield, exit, stat, open, _ };

pub fn read(fd: u32, buffer: []u8) i32 {
    return asm volatile (
        \\ int $0x80
        : [ret] "={eax}" (-> i32),
        : [syscall] "{eax}" (Syscall.read),
          [_] "{ebx}" (fd),
          [_] "{ecx}" (buffer.ptr),
          [_] "{edx}" (buffer.len),
    );
}

pub fn write(fd: u32, buffer: []const u8) void {
    asm volatile (
        \\ int $0x80
        :
        : [syscall] "{eax}" (Syscall.write),
          [_] "{ebx}" (fd),
          [_] "{ecx}" (buffer.ptr),
          [_] "{edx}" (buffer.len),
        : .{ .eax = true });
}

pub fn exec(path: []const u8) i32 {
    return asm volatile (
        \\ int $0x80
        : [ret] "={eax}" (-> i32),
        : [syscall] "{eax}" (Syscall.exec),
          [_] "{ebx}" (path.ptr),
          [_] "{ecx}" (path.len),
    );
}

pub fn sleep(amount: u32) void {
    asm volatile (
        \\ int $0x80
        :
        : [syscall] "{eax}" (Syscall.sleep),
          [_] "{ebx}" (amount),
        : .{ .eax = true });
}

pub fn yield() void {
    asm volatile (
        \\ int $0x80
        :
        : [syscall] "{eax}" (Syscall.yield),
        : .{ .eax = true });
}

pub fn exit(code: u32) void {
    asm volatile (
        \\ int $0x80
        :
        : [syscall] "{eax}" (Syscall.exit),
          [_] "{ebx}" (code),
        : .{ .eax = true });
}

pub fn stat(path: []const u8, out: *root.fs.Stat) void {
    asm volatile (
        \\ int $0x80
        :
        : [syscall] "{eax}" (Syscall.stat),
          [_] "{ebx}" (path.ptr),
          [_] "{ecx}" (path.len),
          [_] "{edx}" (out),
        : .{ .eax = true });
}

pub fn open(path: []const u8) u32 {
    return asm volatile (
        \\ int $0x80
        : [ret] "={eax}" (-> u32),
        : [syscall] "{eax}" (Syscall.open),
          [_] "{ebx}" (path.ptr),
          [_] "{ecx}" (path.len),
    );
}
