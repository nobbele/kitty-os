const root = @import("root");
const console = root.console;
const syscall = root.syscall;

pub const STDIN = 0;
pub const STDOUT = 1;

pub fn init() !void {
    try syscall.registerSyscall(syscall.Syscall.write, syscallWrite);
    try syscall.registerSyscall(syscall.Syscall.read, syscallRead);
}

fn syscallWrite(args: syscall.SyscallArgs) syscall.SyscallResult {
    const fd = args.get(u8, 0);
    const buf_ptr: [*]const u8 = @ptrFromInt(args.get(usize, 1));
    const len = args.get(u32, 2);
    const buf = buf_ptr[0..len];
    // console.println("write({}, 0x{*}, {})", .{ fd, buf, len });

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
    // console.println("read({}, 0x{*}, {})", .{ fd, buf, len });

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
