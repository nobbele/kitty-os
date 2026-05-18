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
const scheduler = @import("scheduler.zig");
const shell = @import("shell.zig");

pub fn kmain(multiboot_info_address: usize) callconv(.{ .x86_sysv = .{} }) noreturn {
    console.init();

    console.println("[multiboot] init", .{});
    multiboot.init(multiboot_info_address);

    arch.init() catch unreachable;

    console.println("[fs] init", .{});
    fs.init() catch unreachable;

    console.println("Executing usermode program", .{});
    // // exec();
    execElf() catch |e| std.debug.panic("Failed to execute ELF: {}", .{e});

    console.println("[shell] start", .{});
    shell.run();
}

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

    const task = try std.heap.page_allocator.create(scheduler.Task);
    task.* = try scheduler.Task.init();

    for (program_headers) |ph| {
        switch (ph.type) {
            .LOAD => {
                console.println("Loading {X}-{X}({X})", .{ ph.vaddr, ph.vaddr + ph.filesz, ph.vaddr + ph.memsz });
                const page_offset = ph.vaddr % root.PAGE_SIZE;
                const aligned_vaddr = std.mem.alignBackward(usize, ph.vaddr, root.PAGE_SIZE);
                const allocated_size = ph.memsz + page_offset;

                const alloc_paddr = pmm.alloc(allocated_size) orelse return error.OutOfMemory;
                console.println("alloc_paddr: {X}", .{alloc_paddr});

                try task.address_space.mapRange(aligned_vaddr, alloc_paddr, allocated_size, .{ .access = .user });

                const dest: [*]u8 = @ptrFromInt(root.KERNEL_BASE + alloc_paddr + page_offset);
                const src: [*]u8 = @ptrFromInt(data_phys + ph.offset);

                @memset(dest[0..ph.memsz], 0);
                @memcpy(dest[0..ph.filesz], src[0..ph.filesz]);
            },
            else => {},
        }
    }

    gdt.setTaskKernelStack(task.kernelStackTop());
    task.frame = .{
        .eax = 0,
        .ebx = 0,
        .ecx = 0,
        .edx = 0,
        .edi = 0,
        .esi = 0,
        .ebp = 0,

        .eip = header.entry,
        .cs = root.USER_CS,
        .flags = 0x200,
        .esp = task.user_stack.virt_top,
        .ss = root.USER_DS,
    };

    console.println("Adding task to scheduler", .{});
    asm volatile ("cli");
    try scheduler.addTask(task);
    const eip = task.frame.eip;
    const esp = task.frame.esp;
    const flags = task.frame.flags;

    scheduler.switchTo(task);
    asm volatile (
        \\ mov %[ds], %%ds
        \\ mov %[ds], %%es
        \\ mov %[ds], %%fs
        \\ mov %[ds], %%gs
        \\
        \\ pushl %[ds] # ss
        \\ pushl %[esp]
        \\ pushl %[flags]
        \\ pushl %[cs]
        \\ pushl %[eip]
        \\ iret
        :
        : [ds] "r" (@as(u32, root.USER_DS)),
          [esp] "r" (esp),
          [flags] "r" (flags),
          [cs] "i" (root.USER_CS),
          [eip] "r" (eip),
    );
}
