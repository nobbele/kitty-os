const std = @import("std");

pub const syscall = @import("syscall.zig");

pub fn readLine(buffer: []u8) !u32 {
    var char: u8 = undefined;
    var count: usize = 0;
    while (count < buffer.len) {
        const res = syscall.read(0, @as(*[1]u8, &char));

        if (res == 0) {
            syscall.yield();
            continue;
        }

        syscall.write(1, @as(*[1]u8, &char));

        if (char == '\n')
            break;

        buffer[count] = char;
        count += 1;
    }

    if (count == buffer.len)
        return error.OutOfBounds;

    return count;
}

fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) !usize {
    // the length of data must not be zero
    std.debug.assert(data.len != 0);

    var consumed: usize = 0;
    const pattern = data[data.len - 1];
    const splat_len = pattern.len * splat;

    // If buffer is not empty write it first
    if (w.end != 0) {
        syscall.write(1, w.buffered());
        w.end = 0;
    }

    // Now write all data except last element
    for (data[0 .. data.len - 1]) |bytes| {
        syscall.write(1, bytes);
        consumed += bytes.len;
    }

    // If out patter (i.e. last element of data) is non zero len then write splat times
    switch (pattern.len) {
        0 => {},
        else => {
            for (0..splat) |_| {
                syscall.write(1, pattern);
            }
        },
    }
    // Now we have to return how many bytes we consumed from data
    consumed += splat_len;
    return consumed;
}

const drain_vtable: std.Io.Writer.VTable = .{ .drain = drain };

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var writer: std.Io.Writer = .{
        .buffer = &.{},
        .end = 0,
        .vtable = &drain_vtable,
    };
    writer.print(fmt, args) catch return;
}

pub fn println(comptime fmt: []const u8, args: anytype) void {
    var writer: std.Io.Writer = .{
        .buffer = &.{},
        .end = 0,
        .vtable = &drain_vtable,
    };
    writer.print(fmt, args) catch return;
    writer.printAsciiChar('\n', .{}) catch return;
}
