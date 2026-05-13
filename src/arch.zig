const gdt = @import("arch/gdt.zig");
const idt = @import("arch/idt.zig");
const mmu = @import("arch/mmu.zig");
const pic = @import("arch/pic.zig");
const pmm = @import("arch/pmm.zig");
const ps2 = @import("arch/ps2.zig");
const console = @import("console.zig");
const multiboot = @import("multiboot.zig");

pub fn init() !void {
    console.println("[pmm] init", .{});
    pmm.init(multiboot.memoryUpper * 1024, multiboot.entries);

    console.println("[mmu] init", .{});
    mmu.init() catch unreachable;

    console.println("[gdt] init", .{});
    gdt.init() catch unreachable;

    console.println("[idt] init", .{});
    idt.init() catch unreachable;

    console.println("[pic] init", .{});
    pic.init();

    asm volatile ("sti");

    asm volatile ("int3");

    console.println("[ps2] init", .{});
    ps2.init();
}
