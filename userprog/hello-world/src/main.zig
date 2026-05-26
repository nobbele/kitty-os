const std = @import("std");

const kitty = @import("kitty");

export fn _start() callconv(.naked) void {
    asm volatile ("call main");
    asm volatile (
        \\ int $0x80
        :
        : [syscall] "{eax}" (5),
          [code] "{ebx}" (0),
    );
}

export fn main() callconv(.{ .x86_sysv = .{} }) void {
    kitty.println("Hello World", .{});
}
