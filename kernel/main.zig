const std = @import("std");
const root = @import("root");
const console = root.console;

pub fn kmain(multiboot_info_address: usize) callconv(.{ .x86_sysv = .{} }) noreturn {
    console.init();

    console.serialPrintln("[multiboot] init", .{});
    root.multiboot.init(multiboot_info_address);

    root.arch.init() catch unreachable;

    console.serialPrintln("[fs] init", .{});
    root.fs.init() catch unreachable;

    root.process.init() catch unreachable;

    console.serialPrintln("Executing usermode program", .{});
    const init = root.process.exec("/shell") catch |e| std.debug.panic("Failed to execute ELF: {}", .{e});

    console.serialPrintln("[proc] Switching to user-mode", .{});
    root.arch.process.startTask(init);

    unreachable;
}
