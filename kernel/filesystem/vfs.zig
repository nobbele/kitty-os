const std = @import("std");
const root = @import("root");
const console = root.console;
const fs = root.fs;

pub fn init() !void {
    root.terminal.println("[vfs] Loading RAMFS", .{});
    try root.fs.ramfs.init();
    try root.fs.devfs.init();
}

pub const Error = error{
    NotAFile,
    NotADirectory,
    OutOfBounds,
    OutOfMemory,
    InvalidOperation,
    AlreadyExists,
};

pub const NodeOps = struct {
    lookup: *const fn (origin: *Node, path: []const u8) Error!?*Node = &stubLookup,
    read: *const fn (node: *Node, buf: []u8, offset: usize) Error!usize,
    write: *const fn (file: *Node, buf: []const u8, offset: usize) Error!usize,
    create: *const fn (dir: *Node, name: []const u8, kind: fs.NodeKind) Error!*Node = &stubCreate,
    stat: *const fn (node: *Node) Error!fs.Stat,
};

fn stubLookup(_: *Node, _: []const u8) Error!?*Node {
    return null;
}

fn stubCreate(_: *Node, _: []const u8, _: fs.NodeKind) Error!*Node {
    return Error.InvalidOperation;
}

// ── Node ──────────────────────────────────────────────────────────────────────

pub const Node = struct {
    name: []const u8,
    data: fs.lib.NodeKind,
    ops: NodeOps,
    fs: *Filesystem,

    pub fn isDir(self: *const Node) bool {
        return self.data == .dir;
    }
};

// ── Filesystem ────────────────────────────────────────────────────────────────

pub const Filesystem = struct {
    name: []const u8,
    root: *Node,
    ops: NodeOps,
};

// ── Mount namespace ───────────────────────────────────────────────────────────

pub const MountEntry = struct {
    mountpoint: ?*Node,
    fs: *Filesystem,
};

pub const Namespace = struct {
    gpa: std.mem.Allocator,
    mounts: std.ArrayList(MountEntry),

    pub fn init(gpa: std.mem.Allocator) !Namespace {
        var mounts: std.ArrayListUnmanaged(MountEntry) = .empty;
        try mounts.append(gpa, .{
            .mountpoint = null,
            .fs = &fs.ramfs.image_ramfs.fs,
        });

        return .{ .gpa = gpa, .mounts = mounts };
    }

    pub fn mount(self: *Namespace, at: *Node, filesystem: *Filesystem) !void {
        if (!at.isDir())
            return Error.NotADirectory;
        try self.mounts.append(self.gpa, .{ .mountpoint = at, .fs = filesystem });
    }

    fn resolve(self: *Namespace, node: *Node) *Node {
        for (self.mounts.items[1..]) |entry| {
            if (entry.mountpoint == node) {
                return entry.fs.root;
            }
        }
        return node;
    }

    pub fn lookup(self: *Namespace, path: []const u8) !?*Node {
        var current: *Node = self.mounts.items[0].fs.root;
        std.debug.assert(current.name.len == 0);

        var it = std.mem.splitScalar(u8, path, '/');
        while (it.next()) |component| {
            if (component.len == 0) continue;
            if (std.mem.eql(u8, component, ".")) continue;
            if (std.mem.eql(u8, component, "..")) return error.NotImplemented;
            if (!current.isDir()) return Error.NotADirectory;

            current = try current.ops.lookup(current, component) orelse return null;
            current = self.resolve(current);
        }

        return current;
    }
};
