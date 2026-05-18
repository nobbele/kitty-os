const gdt = @import("arch/x86/gdt.zig");
const idt = @import("arch/x86/idt.zig");
const pic = @import("arch/x86/pic.zig");
const pmm = @import("arch/x86/pmm.zig");
const ps2 = @import("arch/x86/ps2.zig");
const vmm = @import("arch/x86/vmm.zig");
const console = @import("console.zig");
const multiboot = @import("multiboot.zig");

pub fn init() !void {
    console.println("[pmm] init", .{});
    pmm.init(multiboot.memoryUpper * 1024, multiboot.entries);

    console.println("[vmm] init", .{});
    vmm.init() catch unreachable;

    const t = @import("std").heap.page_allocator.create(u8) catch unreachable;
    t.* = 42;
    console.println("{*} = {}", .{ t, t.* });

    console.println("[gdt] init", .{});
    gdt.init() catch unreachable;

    console.println("[idt] init", .{});
    idt.init() catch unreachable;

    console.println("[pic] init", .{});
    pic.init();

    asm volatile ("sti");

    console.println("[ps2] init", .{});
    ps2.init();
}
