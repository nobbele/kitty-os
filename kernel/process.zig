const std = @import("std");
const root = @import("root");
const vmm = root.arch.vmm;
const pmm = root.arch.pmm;
const console = root.console;
const idt = root.arch.idt;

pub const Task = struct {
    const KERNEL_STACK_SIZE = 0x2000;

    allocator: std.mem.Allocator,

    kernel_stack: []u8 align(16),
    user_stack: Stack,
    frame: idt.InterruptFrame = undefined,

    address_space: vmm.AddressSpace,
    fs_namespace: root.fs.vfs.Namespace,

    sleep_timer: u32 = 0,

    open_files: root.SparseList(*root.fs.Node),

    pub fn init() !Task {
        const allocator = std.heap.page_allocator;

        const address_space = try vmm.AddressSpace.init();
        const user_stack = try Stack.init(&address_space);
        return .{
            .allocator = allocator,
            .kernel_stack = try allocator.alignedAlloc(u8, std.mem.Alignment.@"16", KERNEL_STACK_SIZE),
            .user_stack = user_stack,
            .address_space = address_space,
            .fs_namespace = try .init(allocator),
            .open_files = .empty,
        };
    }

    pub fn free(self: *Task) !void {
        try self.address_space.free();
        try self.user_stack.free();
        // self.allocator.free(self.kernel_stack);
    }

    pub fn kernelStackTop(self: *const Task) usize {
        return @intFromPtr(self.kernel_stack.ptr) + KERNEL_STACK_SIZE;
    }
};

pub fn init() !void {
    try root.syscall.registerSyscall(.exec, struct {
        fn f(args: root.syscall.SyscallArgs) root.syscall.SyscallResult {
            const path_ptr = args.get([*]const u8, 0);
            const len = args.get(usize, 1);
            const path = path_ptr[0..len];
            console.println("exec({s})", .{path});
            _ = exec(path[0..len]) catch |e| {
                console.println("[proc] Error handling exec: {}", .{e});
                return .{ .err = 1 };
            };
            return .void;
        }
    }.f);
    try root.syscall.registerSyscall(.exit, struct {
        fn f(args: root.syscall.SyscallArgs) root.syscall.SyscallResult {
            const code = args.get(u32, 0);
            console.println("exit()", .{});
            exit(code) catch return .{ .err = 1 };
            root.scheduler.scheduleNext(args.frame);
            return .void;
        }
    }.f);
    try root.syscall.registerSyscall(.sleep, struct {
        fn f(args: root.syscall.SyscallArgs) root.syscall.SyscallResult {
            const amount = args.get(u32, 0);
            const current_task = root.scheduler.currentTask();
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
    _ = root.scheduler.removeCurrentTask();
}

pub fn exec(path: []const u8) !*Task {
    console.println("[proc] Executing '{s}'", .{path});

    console.println("[proc] Creating user task", .{});
    const task = try std.heap.page_allocator.create(Task);
    task.* = try .init();

    console.println("[proc] Finding '{s}'", .{path});
    const file_node = try task.fs_namespace.lookup(path) orelse return error.NotFound;
    const file_stat = try file_node.fs.ops.stat(file_node);
    const data = try std.heap.page_allocator.alignedAlloc(u8, .@"4", file_stat.size);
    {
        const bytes_read = try file_node.fs.ops.read(file_node, data, 0);
        if (bytes_read != data.len) {
            console.println("[proc] Read {} / {} bytes", .{ bytes_read, data.len });
            return error.FailedToRead;
        }
    }

    console.println("[proc] Loading ELF header", .{});
    const header: *const std.elf.Elf32.Ehdr = @ptrCast(@alignCast(data.ptr));
    std.debug.assert(std.mem.eql(u8, header.ident[0..4], "\x7fELF"));

    const program_headers_ptr: [*]align(1) const std.elf.Elf32.Phdr = @ptrCast(@alignCast(data.ptr + header.phoff));
    const program_headers = program_headers_ptr[0..header.phnum];

    const section_headers_ptr: [*]align(1) const std.elf.Elf32.Shdr = @ptrCast(@alignCast(data.ptr + header.shoff));
    const section_headers = section_headers_ptr[0..header.shnum];
    _ = section_headers;

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
                const src: [*]u8 = data.ptr[ph.offset..];

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
        .flags = @bitCast(@as(u32, 0x200)),
        .esp = task.user_stack.virt_top - 16,
        .ss = root.USER_DS,
    };

    console.println("[proc] Adding task to scheduler", .{});
    try root.scheduler.addTask(task);

    return task;
}

const Stack = struct {
    phys_start: usize,
    size: usize,
    virt_top: usize,

    pub fn init(address_space: *const vmm.AddressSpace) !Stack {
        const size = 2 * 4096;
        const phys = try pmm.alloc(size);
        const virt_top = root.KERNEL_BASE;
        const virt_start = virt_top - size;

        if (!std.mem.isAligned(virt_start, root.PAGE_SIZE))
            @panic("Virtual start of for stack must be aligned to page");

        if (!std.mem.isAligned(phys, root.PAGE_SIZE))
            @panic("Physical start of stack must be aligned to page");

        try address_space.mapRange(virt_start, phys, size, .{ .access = .user });

        return .{
            .phys_start = phys,
            .size = size,
            .virt_top = virt_top,
        };
    }

    pub fn free(self: *Stack) !void {
        try pmm.free(self.phys_start, self.size);
    }
};
