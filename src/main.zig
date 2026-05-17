const std = @import("std");

const arch = @import("arch.zig");
const gdt = @import("arch/x86/gdt.zig");
const mmu = @import("arch/x86/mmu.zig");
const pmm = @import("arch/x86/pmm.zig");
const console = @import("console.zig");
const multiboot = @import("multiboot.zig");
const root = @import("root.zig");
const shell = @import("shell.zig");

pub fn kmain(multiboot_info_address: usize) callconv(.{ .x86_sysv = .{} }) noreturn {
    console.init();

    console.println("[multiboot] init", .{});
    multiboot.init(multiboot_info_address);

    arch.init() catch unreachable;

    // mmu.map(0x100_000, @intFromPtr(multiboot.modules[0].data.ptr)) catch unreachable;

    // Identity map for simplicity
    const data_phys = @intFromPtr(multiboot.modules[0].data.ptr);
    mmu.map(data_phys, data_phys, .{ .access = .user }) catch unreachable;

    const stack_size = 2 * 4096 - 4;
    const stack_start_phys = pmm.alloc(stack_size) orelse unreachable;
    const stack_top_virt = root.KERNEL_BASE - 4;
    const stack_start_virt = stack_top_virt - stack_size;

    if (!std.mem.isAligned(stack_start_virt, root.PAGE_SIZE))
        @panic("Virtual start of for stack must be aligned to page");

    if (!std.mem.isAligned(stack_start_phys, root.PAGE_SIZE))
        @panic("Physical start of stack must be aligned to page");

    const stack_pages = std.math.divCeil(usize, stack_size, root.PAGE_SIZE) catch unreachable;

    for (0..stack_pages) |stack_page| {
        const virt = stack_start_virt + stack_page * root.PAGE_SIZE;
        const phys = stack_start_phys + stack_page * root.PAGE_SIZE;
        mmu.map(virt, phys, .{ .access = .user }) catch unreachable;
    }

    for (multiboot.modules) |module| {
        console.println("code: {X} {Bi:.1}", .{ module.data, module.data.len });

        gdt.setTaskKernelStack(asm volatile ("mov %%esp, %[esp]"
            : [esp] "=r" (-> usize),
        ));

        asm volatile (
            \\ movw %[ds], %%ax
            \\ mov %%ax, %%ds
            \\ mov %%ax, %%es
            \\ mov %%ax, %%fs
            \\ mov %%ax, %%gs
            \\
            \\ pushl %[ds] # ss
            \\ pushl %[esp]
            \\ pushf # eflags
            \\ pushl %[cs]
            \\ pushl %[eip]
            \\ iret
            :
            : [ds] "i" (root.USER_DS),
              [esp] "r" (stack_top_virt),
              [cs] "i" (root.USER_CS),
              [eip] "r" (@intFromPtr(module.data.ptr)),
            : .{ .ax = true });
    }

    console.println("[shell] start", .{});
    shell.run();
}
