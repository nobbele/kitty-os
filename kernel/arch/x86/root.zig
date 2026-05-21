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
    console.serialPrintln("[pmm] init", .{});
    pmm.init(multiboot.memoryUpper * 1024, multiboot.entries);

    console.serialPrintln("[vmm] init", .{});
    vmm.init() catch unreachable;

    console.serialPrintln("[gdt] init", .{});
    gdt.init() catch unreachable;

    console.serialPrintln("[idt] init", .{});
    idt.init() catch unreachable;

    console.serialPrintln("[pic] init", .{});
    pic.init();

    console.serialPrintln("[timer] init", .{});
    timer.init();

    asm volatile ("sti");

    console.serialPrintln("[ps2] init", .{});
    ps2.init();
}
