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

    console.println("Executing usermode program", .{});
    // // exec();
    execElf() catch |e| std.debug.panic("Failed to execute ELF: {}", .{e});

    console.println("[shell] start", .{});
    root.shell.run();
}

fn execElf() !void {
    const module = &root.multiboot.modules[1];
    const data_phys = module.data_addr;
    try vmm.kernel_address_space.mapRange(data_phys, data_phys, module.data_len, .{ .access = .kernel });

    const header: *const std.elf.Elf32.Ehdr = @ptrFromInt(data_phys);
    std.debug.assert(std.mem.eql(u8, header.ident[0..4], "\x7fELF"));

    const program_headers_ptr: [*]align(1) const std.elf.Elf32.Phdr = @ptrFromInt(data_phys + header.phoff);
    const program_headers = program_headers_ptr[0..header.phnum];

    const section_headers_ptr: [*]align(1) const std.elf.Elf32.Shdr = @ptrFromInt(data_phys + header.shoff);
    const section_headers = section_headers_ptr[0..header.shnum];
    _ = section_headers; // autofix

    const task = try std.heap.page_allocator.create(root.scheduler.Task);
    task.* = try .init();

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

    root.arch.gdt.setTaskKernelStack(task.kernelStackTop());
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
    try root.scheduler.addTask(task);

    console.println("Switching to user-mode", .{});
    root.process.startTask(task);
}
