const std = @import("std");

const arch = @import("arch.zig");
const gdt = @import("arch/x86/gdt.zig");
const mmu = @import("arch/x86/mmu.zig");
const pmm = @import("arch/x86/pmm.zig");
const console = @import("console.zig");
const elf = @import("elf.zig");
const fs = @import("filesystem.zig");
const multiboot = @import("multiboot.zig");
const root = @import("root.zig");
const shell = @import("shell.zig");

pub fn kmain(multiboot_info_address: usize) callconv(.{ .x86_sysv = .{} }) noreturn {
    console.init();

    console.println("[multiboot] init", .{});
    multiboot.init(multiboot_info_address);

    arch.init() catch unreachable;

    fs.init() catch unreachable;

    // exec();
    execElf() catch unreachable;

    console.println("[shell] start", .{});
    shell.run();
}

fn execElf() !void {
    const module = &multiboot.modules[1];
    const data_phys = module.data_addr;
    try mmu.mapRange(data_phys, data_phys, module.data_len, .{ .access = .kernel });

    const data: *const anyopaque = @ptrFromInt(data_phys);
    const header: *const elf.Header = @ptrCast(@alignCast(data));
    std.debug.assert(header.id.magic == elf.MAGIC);
    console.println("{f}", .{std.json.fmt(header, .{ .whitespace = .indent_2 })});

    const program_headers_ptr: [*]align(1) const elf.ProgramHeader = @ptrFromInt(data_phys + header.program_header_offset);
    const program_headers = program_headers_ptr[0..header.program_header_entries];

    const section_headers_ptr: [*]align(1) const elf.SectionHeader = @ptrFromInt(data_phys + header.section_header_offset);
    const section_headers = section_headers_ptr[0..header.section_header_entries];

    for (section_headers) |sh| {
        console.println("{f}", .{std.json.fmt(sh, .{ .whitespace = .indent_2 })});

        // switch (sh.kind) {
        //     .nobits => blk: {
        //         if (sh.size == 0) break :blk;
        //         if (sh.flags.allocated) {

        //         }
        //     },
        //     else => {},
        // }
    }

    for (program_headers) |ph| {
        console.println("{f}", .{std.json.fmt(ph, .{ .whitespace = .indent_2 })});

        switch (ph.kind) {
            .load => {
                const page_offset = ph.vaddr % root.PAGE_SIZE;
                const aligned_vaddr = std.mem.alignBackward(usize, page_offset, root.PAGE_SIZE);

                // mmu.map(aligned_vaddr, 0, .{ .access = .user, . })
                _ = aligned_vaddr; // autofix
            },
            else => {},
        }
    }
}

fn exec() void {
    // Identity map for simplicity
    const data_phys = @intFromPtr(multiboot.modules[0].data_addr.ptr);
    mmu.map(data_phys, data_phys, .{ .access = .user }) catch unreachable;
    mmu.map(0x100_000, data_phys, .{ .access = .user }) catch unreachable;

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
        console.println("code: {X} {Bi:.1}", .{ module.data_addr, module.data_addr.len });

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
              [eip] "r" (@intFromPtr(module.data_addr.ptr)),
            : .{ .ax = true });
    }
}
