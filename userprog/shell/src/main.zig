const std = @import("std");

const kitty = @import("kitty");

export fn main() callconv(.{ .x86_sysv = .{} }) void {
    kitty.println("Welcome to the KittyOS shell!", .{});

    var buffer: [64]u8 = undefined;
    while (true) {
        kitty.print(">", .{});
        const read = kitty.readLine(&buffer) catch 0;
        const cmdline = buffer[0..read];

        var it = std.mem.splitScalar(u8, cmdline, ' ');
        const path = it.next() orelse continue;
        kitty.syscall.exec(path);

        // TODO wait for processes
        for (0..3) |_| kitty.syscall.yield();
    }
}
