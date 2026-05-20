const std = @import("std");
const root = @import("root");
const gdt = root.arch.gdt;
const idt = root.arch.idt;
const pmm = root.arch.pmm;
const vmm = root.arch.vmm;
const console = root.console;

var tasks: std.ArrayList(*Task) = .empty;
var current_idx: usize = 0;

pub fn addTask(task: *Task) !void {
    try tasks.append(std.heap.page_allocator, task);
}

pub fn currentTask() ?*Task {
    if (tasks.items.len == 0) return null;
    return tasks.items[current_idx];
}

pub fn findNextTask() ?*Task {
    for (0..tasks.items.len) |_| {
        current_idx = (current_idx + 1) % tasks.items.len;
        const next = tasks.items[current_idx];

        if (next.sleep_timer == 0) {
            return next;
        }
    }
    return null;
}

pub fn schedule(frame: *idt.InterruptFrame) void {
    if (tasks.items.len == 0) return;

    // Save current task
    tasks.items[current_idx].frame = frame.*;

    // Find the next task
    const next = while (true) {
        const next = findNextTask();

        // Decrease all sleep timers
        for (tasks.items) |task| {
            task.sleep_timer -|= root.arch.timer.SCHEDULE_DT;
        }

        if (next) |task| {
            break task;
        }

        asm volatile ("sti; hlt");
    };

    console.serialPrintln("Scheduling {} / {}", .{ current_idx + 1, tasks.items.len });

    switchTo(next);

    // Restore next task's frame — the stub will iret into it
    frame.* = next.frame;
}

pub fn switchTo(task: *Task) void {
    gdt.setTaskKernelStack(task.kernelStackTop());
    task.address_space.load();
}

pub const Task = struct {
    const KERNEL_STACK_SIZE = 0x2000;

    kernel_stack: []u8 align(16),
    user_stack: Stack,
    address_space: vmm.AddressSpace,
    frame: idt.InterruptFrame = undefined,

    sleep_timer: u32 = 0,

    pub fn init() !Task {
        const address_space = try vmm.AddressSpace.init();
        const user_stack = try setupStack(&address_space);
        return .{
            .kernel_stack = try std.heap.page_allocator.alignedAlloc(u8, std.mem.Alignment.@"16", KERNEL_STACK_SIZE),
            .user_stack = user_stack,
            .address_space = address_space,
        };
    }

    pub fn kernelStackTop(self: *const Task) usize {
        return @intFromPtr(self.kernel_stack.ptr) + KERNEL_STACK_SIZE;
    }
};

const Stack = struct {
    phys_start: usize,
    virt_top: usize,
};

fn setupStack(address_space: *const vmm.AddressSpace) !Stack {
    const size = 2 * 4096 - 4;
    const phys = try pmm.alloc(size);
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
        try address_space.map(page_virt, page_phys, .{ .access = .user });
    }

    return .{ .phys_start = phys, .virt_top = virt_top };
}

// const tasks =

// pub fn addTask()
