const std = @import("std");

const kitty = @import("kitty");

export fn _start() callconv(.naked) void {
    asm volatile ("call main");
}

export fn main() callconv(.{ .x86_sysv = .{} }) void {
    asm volatile (
        \\ mov %[deadbeef], %%eax
        :
        : [deadbeef] "i" (kitty.a),
        : .{ .eax = true });

    var buffer: [64]u8 = undefined;

    var x: usize = asm volatile (""
        : [ret] "={ebx}" (-> usize),
    );
    while (true) {
        x += 1;
        kitty.write(1, std.fmt.bufPrint(&buffer, "Hello World {}\n", .{x}) catch unreachable);
    }
}
