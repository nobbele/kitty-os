const std = @import("std");
const root = @import("root");
const console = root.console;
const fs = root.fs;

var ramfs_instance: *fs.vfs.Filesystem = undefined;

pub fn init() !void {
    root.terminal.println("[vfs] Loading RAMFS", .{});
    ramfs_instance = try fs.ramfs.init();
}

pub const Error = error{
    NotAFile,
    NotADirectory,
    OutOfBounds,
    OutOfMemory,
};

pub const NodeOps = struct {
    lookup: *const fn (origin: *Node, path: []const u8) Error!?*Node,
    read: *const fn (node: *Node, buf: []u8, offset: usize) Error!usize,
    write: *const fn (file: *Node, buf: []const u8, offset: usize) Error!usize,
    create: *const fn (dir: *Node, name: []const u8, kind: fs.NodeKind) Error!*Node,
    stat: *const fn (node: *Node) Error!fs.Stat,
};

pub const Node = struct {
    name: []const u8,
    kind: fs.NodeKind,
    fs: *Filesystem,
};

pub const Filesystem = struct {
    root: *Node,
    ops: *const NodeOps,
};

pub const MountEntry = struct {
    mountpoint: ?*Node,
    fs: *Filesystem,
};

pub const Namespace = struct {
    allocator: std.mem.Allocator,
    mounts: std.ArrayList(MountEntry),

    pub fn init(allocator: std.mem.Allocator) !Namespace {
        var mounts: std.ArrayList(MountEntry) = .empty;
        try mounts.append(allocator, .{
            .mountpoint = null,
            .fs = ramfs_instance,
        });

        return .{
            .allocator = allocator,
            .mounts = mounts,
        };
    }

    // pub fn mount(self: *Namespace, at: *Node, fs: *Filesystem) !void { ... }

    pub fn lookup(self: *Namespace, path: []const u8) !?*Node {
        var current: *Node = self.mounts.items[0].fs.root;
        std.debug.assert(current.name.len == 0);

        var it = std.mem.splitScalar(u8, path, '/');
        while (it.next()) |component| {
            if (component.len == 0) continue;
            if (std.mem.eql(u8, component, ".")) continue;
            if (std.mem.eql(u8, component, "..")) return error.NotImplemented;
            current = try current.fs.ops.lookup(current, component) orelse return null;
        }

        return current;
    }
};
