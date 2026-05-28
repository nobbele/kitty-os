const std = @import("std");
const root = @import("root");
const console = root.console;
const fs = root.fs;
const vfs = fs.vfs;

pub const RamfsNode = struct {
    node: vfs.Node,
    gpa: std.mem.Allocator,
    data: Data,

    pub const Data = union(enum) {
        file: std.ArrayListUnmanaged(u8),
        dir: std.StringHashMapUnmanaged(*RamfsNode),
    };

    pub fn initFile(gpa: std.mem.Allocator, filesystem: *vfs.Filesystem, name: []const u8) RamfsNode {
        return .{
            .node = .{ .name = name, .data = .file, .fs = filesystem, .ops = filesystem.ops },
            .gpa = gpa,
            .data = .{ .file = .empty },
        };
    }

    pub fn initDir(gpa: std.mem.Allocator, filesystem: *vfs.Filesystem, name: []const u8) RamfsNode {
        return .{
            .node = .{ .name = name, .data = .dir, .fs = filesystem, .ops = filesystem.ops },
            .gpa = gpa,
            .data = .{ .dir = .empty },
        };
    }

    pub fn deinit(self: *RamfsNode) void {
        switch (self.data) {
            .file => |*buf| buf.deinit(self.gpa),
            .dir => |*entries| {
                var it = entries.iterator();
                while (it.next()) |e| e.value_ptr.*.deinit();
                entries.deinit(self.gpa);
            },
        }
        self.gpa.destroy(self);
    }
};

pub const Ramfs = struct {
    fs: fs.vfs.Filesystem,
    root_node: RamfsNode,
    gpa: std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator) !*Ramfs {
        const self = try gpa.create(Ramfs);
        const ops: vfs.NodeOps = .{
            .lookup = &nodeLookup,
            .read = &nodeRead,
            .stat = &nodeStat,
            .write = &nodeWrite,
            .create = &nodeCreate,
        };
        self.* = .{
            .fs = .{
                .ops = ops,
                .root = undefined,
                .name = "ramfs",
            },
            .root_node = .{
                .node = .{
                    .name = "",
                    .data = .dir,
                    .fs = &self.fs,
                    .ops = ops,
                },
                .data = .{ .dir = .{} },
                .gpa = gpa,
            },
            .gpa = gpa,
        };
        self.fs.root = &self.root_node.node;
        return self;
    }
};

pub var image_ramfs: *Ramfs = undefined;
pub var devfs_node: *RamfsNode = undefined;

pub fn init() !void {
    const gpa = std.heap.page_allocator;
    image_ramfs = try .init(gpa);
    try loadKernelRamfsTar(gpa, &image_ramfs.root_node);

    devfs_node = try create(&image_ramfs.root_node, "dev", .dir);
}

fn loadKernelRamfsTar(gpa: std.mem.Allocator, root_node: *RamfsNode) !void {
    const module = &root.multiboot.modules[0];
    const data_phys = module.data_addr;
    const data_virt = data_phys + root.KERNEL_BASE;
    const data_ptr: [*]const u8 = @ptrFromInt(data_virt);
    const data = data_ptr[0..module.data_len];

    var reader: std.Io.Reader = .fixed(data);
    var file_name_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var link_name_buffer: [std.fs.max_path_bytes]u8 = undefined;

    var it: std.tar.Iterator = .init(&reader, .{
        .file_name_buffer = &file_name_buffer,
        .link_name_buffer = &link_name_buffer,
    });
    while (try it.next()) |entry| {
        console.println("[fs,ramfs] name: {s}", .{entry.name});

        const name = try gpa.dupe(u8, entry.name);

        const opt_last_sep = std.mem.findScalarLast(u8, name, '/');

        var filename: []const u8 = undefined;
        var dir_node = root_node;
        if (opt_last_sep) |last_sep| {
            const dirname = name[0..last_sep];
            filename = name[last_sep + 1 ..];
            dir_node = try makeDirRecursive(root_node, dirname);
        } else {
            filename = name;
        }

        const file_node = try create(dir_node, filename, .file);

        var file_node_writer = std.Io.Writer.Allocating.fromArrayList(gpa, switch (file_node.data) {
            .file => |*file_data| file_data,
            else => unreachable,
        });

        try it.streamRemaining(entry, &file_node_writer.writer);
        switch (file_node.data) {
            .file => |*file_data| file_data.* = file_node_writer.toArrayList(),
            else => unreachable,
        }
    }
}

pub fn makeDirRecursive(dir: *RamfsNode, path: []const u8) !*RamfsNode {
    switch (dir.data) {
        .dir => {},
        else => return error.NotADirectory,
    }

    var current = dir;
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |comp| {
        current = try create(current, comp, .dir);
    }

    return current;
}

pub fn lookup(origin: *RamfsNode, path: []const u8) vfs.Error!?*RamfsNode {
    var current = origin;
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |comp| {
        switch (current.data) {
            .dir => |entries| current = entries.get(comp) orelse return null,
            .file => if (comp.len == 0) {
                switch (current.data) {
                    .file => {},
                    else => return vfs.Error.NotAFile,
                }
                return current;
            } else return vfs.Error.NotADirectory,
        }
    }

    return current;
}

pub fn readFile(file: *RamfsNode, buf: []u8, offset: usize) vfs.Error!usize {
    const data = switch (file.data) {
        .file => |*data| data,
        else => return vfs.Error.NotAFile,
    };

    if (offset >= data.items.len)
        return vfs.Error.OutOfBounds;

    const src: []const u8 = data.items[offset..];

    const bytes = @min(src.len, buf.len);
    @memcpy(
        buf[0..bytes],
        src[0..bytes],
    );

    return bytes;
}

pub fn readDir(dir: *RamfsNode, buf: []u8, offset: usize) vfs.Error!usize {
    const entries = switch (dir.data) {
        .dir => |*entries| entries,
        else => return vfs.Error.NotADirectory,
    };

    const index = offset / @sizeOf(fs.DirEntry);
    const trimmed = buf[0 .. (buf.len / @sizeOf(fs.DirEntry)) * @sizeOf(fs.DirEntry)];
    const entry_buf: []fs.DirEntry = @alignCast(std.mem.bytesAsSlice(fs.DirEntry, trimmed));

    var it = entries.iterator();
    for (0..index) |_| {
        _ = it.next();
    }

    var it_idx: usize = 0;
    while (it.next()) |entry| : (it_idx += 1) {
        if (it_idx >= entry_buf.len)
            break;

        const name = entry.key_ptr.*;
        entry_buf[it_idx] = .{
            .name_len = name.len,
        };
        @memcpy(entry_buf[it_idx].name[0..name.len], name);
    }

    return it_idx * @sizeOf(fs.DirEntry);
}

fn stat(node: *RamfsNode) vfs.Error!fs.Stat {
    switch (node.data) {
        .file => |data| {
            var res: fs.Stat = .{
                .kind = .file,
                .size = data.items.len,
                .mountpoint_len = node.node.fs.root.name.len,
                .filesystem_len = node.node.fs.name.len,
            };
            @memcpy(res.mountpoint[0..node.node.fs.root.name.len], node.node.fs.root.name);
            @memcpy(res.filesystem[0..node.node.fs.name.len], node.node.fs.name);
            return res;
        },
        .dir => |entries| {
            var res: fs.Stat = .{
                .kind = .dir,
                .size = entries.size * @sizeOf(fs.DirEntry),
                .mountpoint_len = node.node.fs.root.name.len,
                .filesystem_len = node.node.fs.name.len,
            };
            @memcpy(res.mountpoint[0..node.node.fs.root.name.len], node.node.fs.root.name);
            @memcpy(res.filesystem[0..node.node.fs.name.len], node.node.fs.name);
            return res;
        },
    }
}

fn write(file: *RamfsNode, buf: []const u8, offset: usize) vfs.Error!usize {
    const data = switch (file.data) {
        .file => |*data| data,
        else => return vfs.Error.NotAFile,
    };

    if (offset >= data.items.len)
        return vfs.Error.OutOfBounds;

    data.appendSlice(file.gpa, buf) catch return vfs.Error.OutOfMemory;

    return buf.len;
}

fn create(dir: *RamfsNode, name: []const u8, kind: fs.NodeKind) vfs.Error!*RamfsNode {
    const gpa = dir.gpa;

    var entries = switch (dir.data) {
        .dir => |*entries| entries,
        else => return vfs.Error.NotADirectory,
    };

    const node = try gpa.create(RamfsNode);
    node.* = switch (kind) {
        .dir => .initDir(gpa, dir.node.fs, name),
        .file => .initFile(gpa, dir.node.fs, name),
        else => return vfs.Error.InvalidOperation,
    };

    entries.putNoClobber(gpa, name, node) catch return vfs.Error.OutOfMemory;

    return node;
}

pub fn nodeLookup(origin: *fs.vfs.Node, path: []const u8) vfs.Error!?*fs.vfs.Node {
    const target = try lookup(@fieldParentPtr("node", origin), path) orelse return null;
    return &target.node;
}

fn nodeRead(vfsNode: *fs.vfs.Node, buf: []u8, offset: usize) vfs.Error!usize {
    const node: *RamfsNode = @fieldParentPtr("node", vfsNode);
    return try switch (node.node.data) {
        .file => readFile(node, buf, offset),
        .dir => readDir(node, buf, offset),
        else => return vfs.Error.InvalidOperation,
    };
}

fn nodeStat(node: *fs.vfs.Node) vfs.Error!fs.Stat {
    return try stat(@fieldParentPtr("node", node));
}

fn nodeWrite(file: *fs.vfs.Node, buf: []const u8, offset: usize) vfs.Error!usize {
    return try write(@fieldParentPtr("node", file), buf, offset);
}

fn nodeCreate(dir: *fs.vfs.Node, name: []const u8, kind: fs.NodeKind) vfs.Error!*fs.vfs.Node {
    const target = try create(@fieldParentPtr("node", dir), name, kind);
    return &target.node;
}
