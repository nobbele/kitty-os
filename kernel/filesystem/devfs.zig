const std = @import("std");
const root = @import("root");
const console = root.console;
const fs = root.fs;
const vfs = fs.vfs;

pub const Devfs = struct {
    fs: fs.vfs.Filesystem,
    root_node: vfs.Node,
    devices: std.StringHashMapUnmanaged(vfs.Node),
    gpa: std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator) !*Devfs {
        const self = try gpa.create(Devfs);
        const ops: vfs.NodeOps = .{
            .lookup = &lookup,
            .read = &read,
            .write = &write,
            .stat = &stat,
        };
        self.* = .{
            .fs = .{
                .ops = ops,
                .root = &self.root_node,
                .name = "devfs",
            },
            .root_node = .{
                .name = "",
                .data = .dir,
                .fs = &self.fs,
                .ops = ops,
            },
            .devices = .{},
            .gpa = gpa,
        };
        return self;
    }

    pub fn registerDevice(self: *Devfs, name: []const u8, ops: vfs.NodeOps, data: ?*anyopaque) !*vfs.Node {
        _ = data; // autofix
        const result = try self.devices.getOrPut(self.gpa, name);
        if (result.found_existing) {
            self.gpa.free(name);
            return vfs.Error.AlreadyExists;
        }

        result.value_ptr.* = .{
            .fs = &self.fs,
            .data = .device,
            .ops = ops,
            .name = name,
        };
        return result.value_ptr;
    }
};

pub var global_devfs: *Devfs = undefined;

pub fn init() !void {
    const gpa = std.heap.page_allocator;
    global_devfs = try .init(gpa);
}

fn lookup(dir: *vfs.Node, name: []const u8) vfs.Error!?*vfs.Node {
    const self: *Devfs = @fieldParentPtr("root_node", dir);
    return self.devices.getPtr(name);
}

fn read(node: *vfs.Node, buf: []u8, offset: usize) vfs.Error!usize {
    const self: *Devfs = @fieldParentPtr("root_node", node);
    return switch (node.data) {
        .dir => {
            const index = offset / @sizeOf(fs.DirEntry);
            const trimmed = buf[0 .. (buf.len / @sizeOf(fs.DirEntry)) * @sizeOf(fs.DirEntry)];
            const entry_buf: []fs.DirEntry = @alignCast(std.mem.bytesAsSlice(fs.DirEntry, trimmed));

            var it = self.devices.iterator();
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
        },
        else => vfs.Error.InvalidOperation,
    };
}

fn write(_: *vfs.Node, _: []const u8, _: usize) vfs.Error!usize {
    return vfs.Error.InvalidOperation;
}

fn stat(node: *vfs.Node) vfs.Error!fs.Stat {
    const self: *Devfs = @fieldParentPtr("root_node", node);
    var res: fs.Stat = .{
        .kind = node.data,
        .size = self.devices.count() * @sizeOf(fs.DirEntry),
        .mountpoint_len = self.fs.root.name.len,
        .filesystem_len = self.fs.name.len,
    };
    @memcpy(res.mountpoint[0..self.fs.root.name.len], self.fs.root.name);
    @memcpy(res.filesystem[0..self.fs.name.len], self.fs.name);
    return res;
}
