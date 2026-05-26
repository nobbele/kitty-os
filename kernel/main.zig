const std = @import("std");
const root = @import("root");
const console = root.console;
const multiboot = root.multiboot;

const catgirl align(4) = @embedFile("catgirl.raw");

pub fn kmain(multiboot_info_address: usize) callconv(.{ .x86_sysv = .{} }) noreturn {
    console.println("[multiboot] init", .{});
    root.multiboot.init(multiboot_info_address);

    root.arch.init() catch unreachable;

    console.println("[fs] init", .{});
    root.fs.init() catch unreachable;

    console.println("[terminal] init", .{});
    root.terminal.init() catch unreachable;

    root.terminal.putImage(@ptrCast(@alignCast(catgirl)), 183, 243);

    root.process.init() catch unreachable;

    root.terminal.println("[kernel] Loading shell", .{});
    const init = root.process.exec("/shell") catch |e| std.debug.panic("Failed to execute ELF: {}", .{e});

    console.println("[proc] Switching to user-mode", .{});
    root.arch.process.startTask(init);

    unreachable;
}
