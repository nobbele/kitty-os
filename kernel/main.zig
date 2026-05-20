const std = @import("std");
const root = @import("root");
const console = root.console;
const vmm = root.arch.vmm;
const pmm = root.arch.pmm;

pub fn kmain(multiboot_info_address: usize) callconv(.{ .x86_sysv = .{} }) noreturn {
    console.init();

    console.println("[multiboot] init", .{});
    root.multiboot.init(multiboot_info_address);

    @import("arch/x86/root.zig").init() catch unreachable;

    console.println("[fs] init", .{});
    root.fs.init() catch unreachable;

    root.process.init() catch unreachable;

    console.println("Executing usermode program", .{});
    root.process.exec() catch |e| std.debug.panic("Failed to execute ELF: {}", .{e});

    console.println("[shell] start", .{});
    root.shell.run();
}
