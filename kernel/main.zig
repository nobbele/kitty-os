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

const Task = struct {
    const KERNEL_STACK_SIZE = 0x2000;

    kernel_stack: [KERNEL_STACK_SIZE]u8 align(16),

    pub fn kernelStackTop(self: *Task) usize {
        return @intFromPtr(&self.kernel_stack) + KERNEL_STACK_SIZE;
    }
};

fn execElf() !void {
    const module = &multiboot.modules[1];
    const data_phys = module.data_addr;
    try mmu.mapRange(data_phys, data_phys, module.data_len, .{ .access = .kernel });

    const header: *const elf.Header = @ptrFromInt(data_phys);
    std.debug.assert(header.id.magic == elf.MAGIC);
    // console.println("{f}", .{std.json.fmt(header, .{ .whitespace = .indent_1 })});

    const program_headers_ptr: [*]align(1) const elf.ProgramHeader = @ptrFromInt(data_phys + header.program_header_offset);
    const program_headers = program_headers_ptr[0..header.program_header_entries];

    const section_headers_ptr: [*]align(1) const elf.SectionHeader = @ptrFromInt(data_phys + header.section_header_offset);
    const section_headers = section_headers_ptr[0..header.section_header_entries];
    _ = section_headers; // autofix

    for (program_headers) |ph| {
        switch (ph.kind) {
            .load => {
                const page_offset = ph.vaddr % root.PAGE_SIZE;
                const aligned_vaddr = std.mem.alignBackward(usize, ph.vaddr, root.PAGE_SIZE);
                const aligned_size = ph.mem_size + page_offset;

                const alloc_paddr = pmm.alloc(ph.mem_size + page_offset) orelse unreachable;

                try mmu.mapRange(aligned_vaddr, alloc_paddr, aligned_size, .{ .access = .user });

                const alloc_ptr: [*]u8 = @ptrFromInt(ph.vaddr);
                const data_ptr: [*]u8 = @ptrFromInt(data_phys + ph.offset);
                @memcpy(alloc_ptr[0..ph.file_size], data_ptr[0..ph.file_size]);

                const extra = ph.mem_size - ph.file_size;
                @memset(alloc_ptr[ph.file_size .. ph.file_size + extra], 0);
            },
            else => {},
        }
    }

    const task = try std.heap.page_allocator.create(Task);

    const esp_virt = setupStack();

    gdt.setTaskKernelStack(task.kernelStackTop());

    asm volatile (
        \\ mov %%ax, %%ds
        \\ mov %%ax, %%es
        \\ mov %%ax, %%fs
        \\ mov %%ax, %%gs
        \\
        \\ pushl %[ds] # ss
        \\ pushl %[esp]
        \\ pushl $0x200
        \\ pushl %[cs]
        \\ pushl %[eip]
        \\ iret
        :
        : [ds] "{eax}" (@as(u32, root.USER_DS)),
          [esp] "r" (esp_virt),
          [cs] "i" (root.USER_CS),
          [eip] "r" (header.entry_addr),
    );
}

fn setupStack() usize {
    const size = 2 * 4096 - 4;
    const phys = pmm.alloc(size) orelse unreachable;
    const virt_top = root.KERNEL_BASE - 4;
    const virt_start = virt_top - size;

    if (!std.mem.isAligned(virt_start, root.PAGE_SIZE))
        @panic("Virtual start of for stack must be aligned to page");

    if (!std.mem.isAligned(phys, root.PAGE_SIZE))
        @panic("Physical start of stack must be aligned to page");

    const page_count = std.math.divCeil(usize, size, root.PAGE_SIZE) catch unreachable;

    for (0..page_count) |stack_page| {
        const page_virt = virt_start + stack_page * root.PAGE_SIZE;
        const page_phys = phys + stack_page * root.PAGE_SIZE;
        mmu.map(page_virt, page_phys, .{ .access = .user }) catch unreachable;
    }

    return virt_top;
}

fn exec() void {
    // Identity map for simplicity
    const data_phys = @intFromPtr(multiboot.modules[0].data_addr.ptr);
    mmu.map(data_phys, data_phys, .{ .access = .user }) catch unreachable;
    mmu.map(0x100_000, data_phys, .{ .access = .user }) catch unreachable;

    const esp_virt = setupStack();

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
              [esp] "r" (esp_virt),
              [cs] "i" (root.USER_CS),
              [eip] "r" (@intFromPtr(module.data_addr.ptr)),
            : .{ .ax = true });
    }
}
