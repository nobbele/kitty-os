const std = @import("std");
const root = @import("root");
const console = root.console;
const syscall = root.syscall;

pub const STDIN = 0;
pub const STDOUT = 1;

pub fn init() !void {
    try syscall.registerSyscall(syscall.Syscall.write, syscallWrite);
    try syscall.registerSyscall(syscall.Syscall.read, syscallRead);

    console.println("[fs] Loading RAMFS", .{});
    try loadRamfs();
}

const FsNodeKind = union(enum) {
    directory,
    file: []u8,
};

const FsNode = struct {
    name: []const u8,
    children: std.DoublyLinkedList = .{},
    node: std.DoublyLinkedList.Node = .{},
    kind: FsNodeKind,

    fn init(name: []const u8, kind: FsNodeKind) FsNode {
        return .{
            .name = name,
            .kind = kind,
        };
    }

    fn isRoot(self: *const FsNode) bool {
        return self.name.len == 0;
    }

    pub fn format(
        self: *const FsNode,
        writer: *std.Io.Writer,
    ) !void {
        try self.formatWithIndent(writer, 0);
    }

    pub fn formatWithIndent(
        self: *const FsNode,
        writer: *std.Io.Writer,
        indent_base: usize,
    ) !void {
        var indent = indent_base;
        if (!self.isRoot()) {
            for (0..indent) |_| {
                try writer.printAsciiChar(' ', .{});
            }
            try writer.print("/{s}", .{self.name});
            indent += 1;
        }

        switch (self.kind) {
            .file => |file| {
                try writer.print(" ({Bi:.1})", .{file.len});
            },
            else => {},
        }

        var node = self.children.first;

        while (node) |n| {
            if (!self.isRoot() or node != self.children.first) {
                try writer.printAsciiChar('\n', .{});
            }

            const fs_node: *FsNode = @fieldParentPtr("node", n);
            try fs_node.formatWithIndent(writer, indent);

            node = n.next;
        }
    }

    pub fn find(self: *FsNode, path: []const u8) ?*FsNode {
        var it = std.mem.splitScalar(u8, path, '/');
        return self.findIt(&it);
    }

    fn findIt(self: *FsNode, it: *std.mem.SplitIterator(u8, .scalar)) ?*FsNode {
        const opt_head = it.next();
        if (opt_head) |head| {
            if (head.len == 0) return fs_root.findIt(it);

            var child = self.children.first;
            while (child) |n| {
                const child_fs: *FsNode = @fieldParentPtr("node", n);
                if (std.mem.eql(u8, head, child_fs.name)) return child_fs;

                child = n.next;
            }
        } else return self;

        return null;
    }
};

pub var fs_root: FsNode = .init("", .directory);

fn loadRamfs() !void {
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

        const name = try std.heap.page_allocator.dupe(u8, entry.name);

        var allocating = std.Io.Writer.Allocating.init(std.heap.page_allocator);
        try it.streamRemaining(entry, &allocating.writer);
        const copied_data = try allocating.toOwnedSlice();

        const fs_node = try std.heap.page_allocator.create(FsNode);
        fs_node.* = .init(name, .{ .file = copied_data });
        fs_root.children.append(&fs_node.node);
    }

    console.println("{f}", .{fs_root});
}

fn syscallWrite(args: syscall.SyscallArgs) syscall.SyscallResult {
    const fd = args.get(u8, 0);
    const buf_ptr = args.get([*]const u8, 1);
    const len = args.get(u32, 2);
    const buf = buf_ptr[0..len];
    // console.serialPrintln("write({}, 0x{*}, {})", .{ fd, buf, len });

    if (fd == 0) return .{ .err = 1 };
    if (fd == 1) return writeStdout(buf);

    // TODO filesystem
    return .{ .err = 2 };
}

fn syscallRead(args: syscall.SyscallArgs) syscall.SyscallResult {
    const fd = args.get(u8, 0);
    const buf_ptr: [*]u8 = @ptrFromInt(args.get(usize, 1));
    const len = args.get(u32, 2);
    const buf = buf_ptr[0..len];
    // console.serialPrintln("read({}, 0x{*}, {})", .{ fd, buf, len });

    if (fd == 0) return readStdin(buf);
    if (fd == 1) return .{ .err = 1 };

    // TODO filesystem
    return .{ .err = 2 };
}

fn writeStdout(buf: []const u8) syscall.SyscallResult {
    console.printString(buf);
    return .{ .ok = buf.len };
}

fn readStdin(buf: []u8) syscall.SyscallResult {
    var chars_read: usize = 0;
    while (root.keyboard.tryReadKey()) |key| {
        buf[chars_read] = key;
        chars_read += 1;

        if (chars_read >= buf.len) break;
    }
    return .{ .ok = chars_read };
}
