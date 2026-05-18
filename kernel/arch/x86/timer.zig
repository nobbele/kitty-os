const console = @import("../../console.zig");
const scheduler = @import("../../scheduler.zig");
const idt = @import("idt.zig");
const interrupts = @import("interrupts.zig");
const pic = @import("pic.zig");
const pit = @import("pit.zig");

pub fn init() void {
    interrupts.registerIrq(0, timerHandler);
    pic.clearIrqMask(0);

    pit.init(0, 100);
}

fn timerHandler(frame: *idt.InterruptFrame) void {
    if (!frame.fromUser()) return;
    scheduler.schedule(frame);
}
