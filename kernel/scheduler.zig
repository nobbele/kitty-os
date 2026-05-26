const std = @import("std");
const root = @import("root");
const gdt = root.arch.gdt;
const idt = root.arch.idt;
const pmm = root.arch.pmm;
const vmm = root.arch.vmm;
const console = root.console;
const process = root.process;

var tasks: std.ArrayList(*process.Task) = .empty;
var current_idx: usize = 0;

pub fn addTask(task: *process.Task) !void {
    try tasks.append(std.heap.page_allocator, task);
    console.println("[sched] Added task #{}", .{tasks.items.len});
}

pub fn currentTask() *process.Task {
    if (current_idx >= tasks.items.len)
        @panic("Current task doesn't exist");
    return tasks.items[current_idx];
}

pub fn removeCurrentTask() *process.Task {
    console.println("[sched] Removing task #{}", .{current_idx + 1});
    return tasks.swapRemove(current_idx);
}

pub fn findNextTask() ?*process.Task {
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
    if (tasks.items.len != 0) {
        // Save current task
        tasks.items[current_idx].frame = frame.*;
    }

    scheduleNext(frame);
}

pub fn scheduleNext(frame: *idt.InterruptFrame) void {
    while (tasks.items.len == 0) {
        console.println("[sched] No more tasks, shutting down", .{});
        root.arch.port.outw(0x604, 0x2000);
        asm volatile ("hlt");
    }

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

        // console.serialPrintln("[sched] Nothing to schedule, halting", .{});
        asm volatile ("sti; hlt");
    };

    // console.serialPrintln("Scheduling #{} / {}", .{ current_idx + 1, tasks.items.len });

    switchTo(next);

    // Restore next task's frame — the stub will iret into it
    frame.* = next.frame;
}

pub fn switchTo(task: *process.Task) void {
    gdt.setTaskKernelStack(task.kernelStackTop());
    task.address_space.load();
}
