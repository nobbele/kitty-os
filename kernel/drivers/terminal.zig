const std = @import("std");
const root = @import("root");
const fs = root.fs;
const vfs = fs.vfs;

pub var node: *vfs.Node = undefined;

pub fn init() !void {
    node = try root.fs.devfs.global_devfs.registerDevice("terminal", .{
        .read = &read,
        .write = &write,
        .stat = &stat,
    }, null);
}

fn read(_: *vfs.Node, buf: []u8, _: usize) vfs.Error!usize {
    var chars_read: usize = 0;
    while (chars_read < buf.len) {
        const key = while (true) {
            if (root.keyboard.tryReadKey()) |k| break k;
            asm volatile ("sti; hlt");
        };

        buf[chars_read] = key;
        chars_read += 1;

        if (key == '\n') break;
    }

    return chars_read;
}

fn write(_: *vfs.Node, buf: []const u8, _: usize) vfs.Error!usize {
    root.terminal.printString(buf);
    return vfs.Error.InvalidOperation;
}

fn stat(_: *vfs.Node) vfs.Error!fs.Stat {
    var res: fs.Stat = .{
        .kind = .device,
        .size = 0,
        .mountpoint_len = node.fs.root.name.len,
        .filesystem_len = node.fs.name.len,
    };
    @memcpy(res.mountpoint[0..node.fs.root.name.len], node.fs.root.name);
    @memcpy(res.filesystem[0..node.fs.name.len], node.fs.name);
    return res;
}
