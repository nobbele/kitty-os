const std = @import("std");
const root = @import("root");
const console = root.console;
const syscall = root.syscall;
pub const lib = root.lib.fs;
pub const NodeKind = lib.NodeKind;
pub const Stat = lib.Stat;
pub const DirEntry = lib.DirEntry;
pub const STDIN = lib.STDIN;
pub const STDOUT = lib.STDOUT;

pub const ramfs = @import("ramfs.zig");
pub const vfs = @import("vfs.zig");
pub const Node = vfs.Node;

pub fn init() !void {
    try syscall.registerSyscall(syscall.Syscall.write, syscallWrite);
    try syscall.registerSyscall(syscall.Syscall.read, syscallRead);
    try syscall.registerSyscall(syscall.Syscall.stat, syscallStat);
    try syscall.registerSyscall(syscall.Syscall.open, syscallOpen);

    console.println("[fs] Loading VFS", .{});
    try vfs.init();
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
    const buf_ptr = args.get([*]u8, 1);
    const len = args.get(u32, 2);
    const buf = buf_ptr[0..len];
    // console.serialPrintln("read({}, 0x{*}, {})", .{ fd, buf, len });

    if (fd == 0) return readStdin(buf);
    if (fd == 1) return .{ .err = 1 };

    const task = root.scheduler.currentTask();
    const node = task.open_files.array.items[fd - lib.StdFd.count] orelse {
        return .{ .err = 1 };
    };

    const r = node.fs.ops.read(node, buf, 0) catch return .{ .err = 2 };

    return .{ .ok = r };
}

fn syscallStat(args: syscall.SyscallArgs) syscall.SyscallResult {
    const fd = args.get(u32, 0);

    const stat_ptr = args.get(*lib.Stat, 1);

    if (fd < lib.StdFd.count)
        return .{ .err = 2 };

    const task = root.scheduler.currentTask();
    const node = task.open_files.array.items[fd - lib.StdFd.count] orelse {
        return .{ .err = 1 };
    };

    stat_ptr.* = node.fs.ops.stat(node) catch {
        return .{ .err = 3 };
    };

    return .void;
}

fn syscallOpen(args: syscall.SyscallArgs) syscall.SyscallResult {
    const path_ptr = args.get([*]const u8, 0);
    const path_len = args.get(u32, 1);
    const path = path_ptr[0..path_len];
    // console.serialPrintln("open({s})", .{path});

    const task = root.scheduler.currentTask();
    const node = task.fs_namespace.lookup(path) catch {
        return .{ .err = 2 };
    } orelse {
        return .{ .err = 1 };
    };

    const fidx = task.open_files.add(std.heap.page_allocator, node) catch {
        return .{ .err = 3 };
    };

    return .{ .ok = fidx + lib.StdFd.count };
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
