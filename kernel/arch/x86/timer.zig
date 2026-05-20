const root = @import("root");
const console = root.console;
const scheduler = root.scheduler;

const idt = @import("idt.zig");
const interrupts = @import("interrupts.zig");
const pic = @import("pic.zig");
const pit = @import("pit.zig");

pub const SCHEDULE_DT: u32 = 10;
pub const SCHEDULE_FREQ: u32 = 1000 / SCHEDULE_DT;

pub fn init() void {
    interrupts.registerIrq(0, timerHandler);
    pic.clearIrqMask(0);

    pit.init(0, SCHEDULE_FREQ);
}

fn timerHandler(frame: *idt.InterruptFrame) void {
    if (!frame.fromUser()) return;
    root.arch.pic.sendEoi(32);
    scheduler.schedule(frame);
}
