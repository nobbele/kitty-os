const std = @import("std");
const root = @import("root");
const fs = root.fs;
const vfs = fs.vfs;

var node: *vfs.Node = undefined;

pub fn init() !void {
    node = try root.fs.devfs.global_devfs.registerDevice("serial", .{
        .read = &read,
        .write = &write,
        .stat = &stat,
    }, null);
}

fn read(_: *vfs.Node, _: []u8, _: usize) vfs.Error!usize {
    return vfs.Error.InvalidOperation;
}

fn write(_: *vfs.Node, _: []const u8, _: usize) vfs.Error!usize {
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
