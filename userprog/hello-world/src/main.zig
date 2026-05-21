const std = @import("std");

const kitty = @import("kitty");

export fn main() callconv(.{ .x86_sysv = .{} }) void {
    kitty.println("Hello World", .{});
}
