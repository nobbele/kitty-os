const std = @import("std");

const arch = @import("arch.zig");
const gdt = @import("arch/x86/gdt.zig");
const mmu = @import("arch/x86/mmu.zig");
const pmm = @import("arch/x86/pmm.zig");
const vmm = @import("arch/x86/vmm.zig");
const console = @import("console.zig");
const fs = @import("filesystem.zig");
const multiboot = @import("multiboot.zig");
const root = @import("root.zig");
const shell = @import("shell.zig");

pub fn kmain(multiboot_info_address: usize) callconv(.{ .x86_sysv = .{} }) noreturn {
    console.init();

    console.println("[multiboot] init", .{});
    multiboot.init(multiboot_info_address);

    arch.init() catch unreachable;

    console.println("[fs] init", .{});
    fs.init() catch unreachable;

    console.println("Executing usermode program", .{});
    // exec();
    execElf() catch |e| std.debug.panic("Failed to execute ELF: {}", .{e});

    console.println("[shell] start", .{});
    shell.run();
}

const Task = struct {
    const KERNEL_STACK_SIZE = 0x2000;

    kernel_stack: [KERNEL_STACK_SIZE]u8 align(16) = undefined,
    user_stack: Stack,
    address_space: vmm.AddressSpace,

    pub fn init() !Task {
        return .{
            .user_stack = try setupStack(),
            .address_space = try vmm.AddressSpace.init(),
        };
    }

    pub fn kernelStackTop(self: *Task) usize {
        return @intFromPtr(&self.kernel_stack) + KERNEL_STACK_SIZE;
    }
};

fn execElf() !void {
    const module = &multiboot.modules[1];
    const data_phys = module.data_addr;
    try vmm.kernel_address_space.mapRange(data_phys, data_phys, module.data_len, .{ .access = .kernel });

    const header: *const std.elf.Elf32.Ehdr = @ptrFromInt(data_phys);
    std.debug.assert(std.mem.eql(u8, header.ident[0..4], "\x7fELF"));

    const program_headers_ptr: [*]align(1) const std.elf.Elf32.Phdr = @ptrFromInt(data_phys + header.phoff);
    const program_headers = program_headers_ptr[0..header.phnum];

    const section_headers_ptr: [*]align(1) const std.elf.Elf32.Shdr = @ptrFromInt(data_phys + header.shoff);
    const section_headers = section_headers_ptr[0..header.shnum];
    _ = section_headers; // autofix

    const task = try std.heap.page_allocator.create(Task);
    task.* = try Task.init();

    for (program_headers) |ph| {
        switch (ph.type) {
            .LOAD => {
                const page_offset = ph.vaddr % root.PAGE_SIZE;
                const aligned_vaddr = std.mem.alignBackward(usize, ph.vaddr, root.PAGE_SIZE);
                const allocated_size = ph.memsz + page_offset;

                const alloc_paddr = pmm.alloc(allocated_size) orelse return error.OutOfMemory;

                try vmm.kernel_address_space.mapRange(alloc_paddr, alloc_paddr, allocated_size, .{ .access = .user });
                try task.address_space.mapRange(aligned_vaddr, alloc_paddr, allocated_size, .{ .access = .user });

                const dest: [*]u8 = @ptrFromInt(alloc_paddr + page_offset);
                const src: [*]u8 = @ptrFromInt(data_phys + ph.offset);

                @memset(dest[0..ph.memsz], 0);
                @memcpy(dest[0..ph.filesz], src[0..ph.filesz]);
            },
            else => {},
        }
    }

    gdt.setTaskKernelStack(task.kernelStackTop());
    console.println("Jumping to usermode", .{});

    const entry = header.entry;
    const esp = task.user_stack.virt_top;

    task.address_space.load();
    asm volatile (
        \\ mov %[ds], %%ds
        \\ mov %[ds], %%es
        \\ mov %[ds], %%fs
        \\ mov %[ds], %%gs
        \\
        \\ pushl %[ds] # ss
        \\ pushl %[esp]
        \\ pushl $0x200
        \\ pushl %[cs]
        \\ pushl %[eip]
        \\ iret
        :
        : [ds] "r" (@as(u32, root.USER_DS)),
          [esp] "r" (esp),
          [cs] "i" (root.USER_CS),
          [eip] "r" (entry),
    );
}

const Stack = struct {
    phys_start: usize,
    virt_top: usize,
};

fn setupStack() !Stack {
    const size = 2 * 4096 - 4;
    const phys = pmm.alloc(size) orelse return error.OutOfMemory;
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
        try vmm.kernel_address_space.map(page_virt, page_phys, .{ .access = .user });
    }

    return .{ .phys_start = phys, .virt_top = virt_top };
}
