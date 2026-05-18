const root = @import("root");
const console = root.console;
const multiboot = root.multiboot;

pub const gdt = @import("gdt.zig");
pub const idt = @import("idt.zig");
pub const pic = @import("pic.zig");
pub const pmm = @import("pmm.zig");
pub const port = @import("port.zig");
pub const process = @import("process.zig");
pub const ps2 = @import("ps2.zig");
pub const timer = @import("timer.zig");
pub const vmm = @import("vmm.zig");

pub fn init() !void {
    console.println("[pmm] init", .{});
    pmm.init(multiboot.memoryUpper * 1024, multiboot.entries);

    console.println("[vmm] init", .{});
    vmm.init() catch unreachable;

    console.println("[gdt] init", .{});
    gdt.init() catch unreachable;

    console.println("[idt] init", .{});
    idt.init() catch unreachable;

    console.println("[pic] init", .{});
    pic.init();

    console.println("[timer] init", .{});
    timer.init();

    asm volatile ("sti");

    console.println("[ps2] init", .{});
    ps2.init();
}
