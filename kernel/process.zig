const std = @import("std");
const root = @import("root");
const vmm = root.arch.vmm;
const pmm = root.arch.pmm;
const console = root.console;

pub fn init() !void {
    try root.syscall.registerSyscall(.exec, struct {
        fn f(args: root.syscall.SyscallArgs) root.syscall.SyscallResult {
            _ = args; // autofix
            // console.println("exec()", .{});
            exec() catch unreachable;
            return .void;
        }
    }.f);
    try root.syscall.registerSyscall(.exit, struct {
        fn f(args: root.syscall.SyscallArgs) root.syscall.SyscallResult {
            const code = args.get(u32, 0);
            // console.println("exit()", .{});
            exit(code) catch unreachable;
            root.scheduler.schedule(args.frame);
            return .void;
        }
    }.f);
    try root.syscall.registerSyscall(.sleep, struct {
        fn f(args: root.syscall.SyscallArgs) root.syscall.SyscallResult {
            const amount = args.get(u32, 0);
            const current_task = root.scheduler.currentTask() orelse unreachable;
            // console.println("sleep({})", .{amount});
            current_task.sleep_timer = amount;
            root.scheduler.schedule(args.frame);
            return .void;
        }
    }.f);
    try root.syscall.registerSyscall(.yield, struct {
        fn f(args: root.syscall.SyscallArgs) root.syscall.SyscallResult {
            // console.println("yield()", .{});
            root.scheduler.schedule(args.frame);
            return .void;
        }
    }.f);
}

pub fn exit(code: u32) !void {
    _ = code; // autofix
    const task = root.scheduler.removeCurrentTask();
    try task.free();
}

pub fn exec() !void {
    const module = &root.multiboot.modules[0];
    const data_phys = module.data_addr;
    const data_virt = data_phys + root.KERNEL_BASE;

    console.println("[proc] Loading ELF header", .{});
    const header: *const std.elf.Elf32.Ehdr = @ptrFromInt(data_virt);
    std.debug.assert(std.mem.eql(u8, header.ident[0..4], "\x7fELF"));

    const program_headers_ptr: [*]align(1) const std.elf.Elf32.Phdr = @ptrFromInt(data_virt + header.phoff);
    const program_headers = program_headers_ptr[0..header.phnum];

    const section_headers_ptr: [*]align(1) const std.elf.Elf32.Shdr = @ptrFromInt(data_virt + header.shoff);
    const section_headers = section_headers_ptr[0..header.shnum];
    _ = section_headers;

    console.println("[proc] Creating user task", .{});
    const task = try std.heap.page_allocator.create(root.scheduler.Task);
    task.* = try .init();

    console.println("[proc] Loading program into memory", .{});
    for (program_headers) |ph| {
        switch (ph.type) {
            .LOAD => {
                console.println("[proc] Loading {X}-{X}({X})", .{ ph.vaddr, ph.vaddr + ph.filesz, ph.vaddr + ph.memsz });
                const page_offset = ph.vaddr % root.PAGE_SIZE;
                const aligned_vaddr = std.mem.alignBackward(usize, ph.vaddr, root.PAGE_SIZE);
                const allocated_size = ph.memsz + page_offset;

                const alloc_paddr = try pmm.alloc(allocated_size);
                console.println("[proc] Writing 0x{X} bytes to 0x{X}", .{ ph.filesz, root.KERNEL_BASE + alloc_paddr });

                const dest: [*]u8 = @ptrFromInt(root.KERNEL_BASE + alloc_paddr + page_offset);
                const src: [*]u8 = @ptrFromInt(data_virt + ph.offset);

                console.println("[proc] Zeroing {*}-{*}", .{ dest, dest + ph.memsz });
                @memset(dest[0..ph.memsz], 0);

                console.println("[proc] Copying {*} -> {*} ({} bytes)", .{ src, dest, ph.filesz });
                @memcpy(dest[0..ph.filesz], src[0..ph.filesz]);

                try task.address_space.mapRange(aligned_vaddr, alloc_paddr, allocated_size, .{ .access = .user });
            },
            else => {},
        }
    }

    console.println("[proc] Setting up task frame", .{});
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

    console.println("[proc] Adding task to scheduler", .{});
    asm volatile ("cli");
    try root.scheduler.addTask(task);

    console.println("[proc] Switching to user-mode", .{});
    root.arch.process.startTask(task);
}
