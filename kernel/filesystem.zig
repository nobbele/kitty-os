const console = @import("console.zig");
const syscall = @import("syscall.zig");

pub const STDIN = 0;
pub const STDOUT = 1;

pub fn init() !void {
    try syscall.registerSyscall(syscall.Syscall.write, syscallWrite);
}

fn syscallWrite(args: syscall.SyscallArgs) syscall.SyscallResult {
    const fd = args.get(u8, 0);
    const buf_ptr: [*]const u8 = @ptrFromInt(0x100_000 + args.get(usize, 1));
    const len = args.get(u32, 2);
    const buf = buf_ptr[0..len];
    console.println("write({}, 0x{*}, {})", .{ fd, buf, len });

    if (fd == 0) return .{ .err = 1 };
    if (fd == 1) return writeStdout(buf);

    // TODO filesystem
    return .{ .err = 2 };
}

fn writeStdout(buf: []const u8) syscall.SyscallResult {
    console.printString(buf);
    return .{ .ok = buf.len };
}
