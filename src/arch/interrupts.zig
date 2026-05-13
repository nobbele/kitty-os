const std = @import("std");
const builtin = @import("builtin");

const console = @import("../console.zig");
const pic = @import("pic.zig");

var hardware_interrupt_handlers = std.mem.zeroes([pic.VEC_END - pic.VEC_START]?*const fn () void);

pub fn register_hardware_interrupt(irq: u8, onInterrupt: fn () void) void {
    hardware_interrupt_handlers[irq] = onInterrupt;
    pic.clearIrqMask(irq);
}

pub fn handler(irq: u8, code: usize) void {
    switch (irq) {
        0...31 => {
            console.println("Exception: 0x{X} ({})", .{ irq, code });
        },
        pic.VEC_START...(pic.VEC_END - 1) => {
            const hw_irq = irq - pic.VEC_START;
            // console.println("Hardware IRQ: 0x{X}", .{hw_irq});
            const hw_handler = hardware_interrupt_handlers[hw_irq];
            if (comptime builtin.mode != .ReleaseFast) {
                if (hw_handler == null)
                    @panic("Tried to call non-existent hardware interrupt handler");
            }

            hw_handler.?();

            pic.sendEoi(irq);
        },
        else => {
            console.println("Unknown IRQ: 0x{X} ({})", .{ irq, code });
        },
    }
}
