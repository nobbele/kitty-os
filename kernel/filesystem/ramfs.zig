const std = @import("std");
const root = @import("root");
const console = root.console;
const fs = root.fs;
const Error = fs.vfs.Error;

pub const RamfsNode = struct {
    allocator: std.mem.Allocator,
    kind: union(fs.NodeKind) {
        file: std.ArrayList(u8),
        directory: std.StringHashMapUnmanaged(*RamfsNode),
    },
    node: fs.vfs.Node,

    pub fn name(self: *const RamfsNode) []const u8 {
        return self.node.name;
    }

    pub fn initFile(allocator: std.mem.Allocator, fs_instance: *fs.vfs.Filesystem, filename: []const u8) RamfsNode {
        return .{
            .allocator = allocator,
            .kind = .{
                .file = .empty,
            },
            .node = .{
                .name = filename,
                .kind = .file,
                .fs = fs_instance,
            },
        };
    }

    pub fn initDir(allocator: std.mem.Allocator, fs_instance: *fs.vfs.Filesystem, dirname: []const u8) RamfsNode {
        return .{
            .allocator = allocator,
            .kind = .{
                .directory = .{},
            },
            .node = .{
                .name = dirname,
                .kind = .directory,
                .fs = fs_instance,
            },
        };
    }
};

pub const ramfs_ops = fs.vfs.NodeOps{
    .lookup = &nodeLookup,
    .read = &nodeRead,
    .stat = &nodeStat,
    .write = &nodeWrite,
    .create = &nodeCreate,
};

pub fn init() !*fs.vfs.Filesystem {
    const allocator = std.heap.page_allocator;

    const fs_instance = try allocator.create(fs.vfs.Filesystem);
    fs_instance.* = .{
        .ops = &ramfs_ops,
        .root = undefined,
    };

    const root_node = try allocator.create(RamfsNode);
    root_node.* = .initDir(allocator, fs_instance, "");
    fs_instance.root = &root_node.node;

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

        const name = try allocator.dupe(u8, entry.name);

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

        var file_node_writer = std.Io.Writer.Allocating.fromArrayList(allocator, switch (file_node.kind) {
            .file => |*file_data| file_data,
            else => unreachable,
        });

        try it.streamRemaining(entry, &file_node_writer.writer);
        switch (file_node.kind) {
            .file => |*file_data| file_data.* = file_node_writer.toArrayList(),
            else => unreachable,
        }
    }

    return fs_instance;
}

pub fn makeDirRecursive(dir: *RamfsNode, path: []const u8) !*RamfsNode {
    std.debug.assert(switch (dir.kind) {
        .directory => true,
        else => false,
    });

    var current = dir;
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |comp| {
        current = try create(current, comp, .directory);
    }

    return current;
}

pub fn lookup(origin: *RamfsNode, path: []const u8) Error!?*RamfsNode {
    var current = origin;
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |comp| {
        switch (current.kind) {
            .directory => |entries| current = entries.get(comp) orelse return null,
            .file => if (comp.len == 0) {
                std.debug.assert(switch (current.kind) {
                    .file => true,
                    else => false,
                });
                return current;
            } else return Error.NotADirectory,
        }
    }

    return current;
}

pub fn readFile(file: *RamfsNode, buf: []u8, offset: usize) Error!usize {
    const data = switch (file.kind) {
        .file => |*data| data,
        else => return Error.NotAFile,
    };

    if (offset >= data.items.len)
        return Error.OutOfBounds;

    const src: []const u8 = data.items[offset..];

    const bytes = @min(src.len, buf.len);
    @memcpy(
        buf[0..bytes],
        src[0..bytes],
    );

    return bytes;
}

pub fn readDir(file: *RamfsNode, buf: []u8, offset: usize) Error!usize {
    const entries = switch (file.kind) {
        .directory => |*entries| entries,
        else => return Error.NotAFile,
    };

    const index = offset / @sizeOf(fs.DirEntry);
    const entry_buf: []fs.DirEntry = @alignCast(std.mem.bytesAsSlice(fs.DirEntry, buf));

    var it = entries.iterator();
    for (0..index) |_| {
        _ = it.next();
    }

    var it_idx: usize = 0;
    while (it.next()) |entry| : (it_idx += 1) {
        if (it_idx >= entry_buf.len)
            break;

        const name = entry.key_ptr;
        entry_buf[it_idx] = .{
            .name = name.ptr,
            .name_len = name.len,
        };
    }

    return it_idx * @sizeOf(fs.DirEntry);
}

fn stat(node: *RamfsNode) Error!fs.Stat {
    switch (node.kind) {
        .file => |data| {
            return .{
                .kind = .file,
                .size = data.items.len,
            };
        },
        .directory => |entries| {
            return .{
                .kind = .directory,
                .size = entries.size * @sizeOf(fs.DirEntry),
            };
        },
    }
}

fn write(file: *RamfsNode, buf: []const u8, offset: usize) Error!usize {
    const data = switch (file.kind) {
        .file => |*data| data,
        else => return Error.NotAFile,
    };

    if (offset >= data.items.len)
        return Error.OutOfBounds;

    data.appendSlice(file.allocator, buf) catch return Error.OutOfMemory;

    return buf.len;
}

fn create(dir: *RamfsNode, name: []const u8, kind: fs.NodeKind) Error!*RamfsNode {
    const allocator = dir.allocator;

    var entries = switch (dir.kind) {
        .directory => |*entries| entries,
        else => return Error.NotADirectory,
    };

    const node = try allocator.create(RamfsNode);
    node.* = switch (kind) {
        .directory => .initDir(allocator, dir.node.fs, name),
        .file => .initFile(allocator, dir.node.fs, name),
    };

    entries.putNoClobber(dir.allocator, name, node) catch return Error.OutOfMemory;

    return node;
}

pub fn nodeLookup(origin: *fs.vfs.Node, path: []const u8) Error!?*fs.vfs.Node {
    const target = try lookup(@fieldParentPtr("node", origin), path) orelse return null;
    return &target.node;
}

fn nodeRead(vfsNode: *fs.vfs.Node, buf: []u8, offset: usize) Error!usize {
    const node: *RamfsNode = @fieldParentPtr("node", vfsNode);
    return try switch (node.kind) {
        .file => readFile(node, buf, offset),
        .directory => readDir(node, buf, offset),
    };
}

fn nodeStat(node: *fs.vfs.Node) Error!fs.Stat {
    return try stat(@fieldParentPtr("node", node));
}

fn nodeWrite(file: *fs.vfs.Node, buf: []const u8, offset: usize) Error!usize {
    return try write(@fieldParentPtr("node", file), buf, offset);
}

fn nodeCreate(dir: *fs.vfs.Node, name: []const u8, kind: fs.NodeKind) Error!*fs.vfs.Node {
    const target = try create(@fieldParentPtr("node", dir), name, kind);
    return &target.node;
}
