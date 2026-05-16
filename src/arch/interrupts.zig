const std = @import("std");
const builtin = @import("builtin");

const console = @import("../console.zig");
const root = @import("../root.zig");
const pic = @import("pic.zig");

var hardware_interrupt_handlers = std.mem.zeroes([pic.VEC_END - pic.VEC_START]?*const fn () void);

pub fn registerHardwareInterrupt(irq: u8, onInterrupt: fn () void) void {
    hardware_interrupt_handlers[irq] = onInterrupt;
    pic.clearIrqMask(irq);
}

const Exception = enum {
    division_error,
    debug,
    nmi,
    breakpoint,
    overflow,
    bound_range_exceeded,
    invalid_opcode,
    device_not_available,
    double_fault,
    unused0,
    invalid_tss,
    segment_not_present,
    stack_segment_fault,
    general_protection_fault,
    page_fault,
    reserved0,
    x87_fp,
    alignment_check,
    machine_check,
    simd_fp,
    virtualization,
    control_protection,
    reserved1,
    hypervisor_injection,
    vmm_communication,
    security,
    reserved2,
    triple_fault,
    unused1,
};

pub const InterruptStackFrame = extern struct {
    ip: usize,
    cs: usize,
    flags: usize,

    pub fn format(
        self: InterruptStackFrame,
        writer: *std.Io.Writer,
    ) !void {
        try writer.print("ip=0x{X} cs=0x{X} flags=0x{X}", .{ self.ip, self.cs, self.flags });
    }
};

pub fn handler(frame: *InterruptStackFrame, irq: u8, code: usize) void {
    switch (irq) {
        0...31 => {
            const exception: Exception = @enumFromInt(irq);
            console.println("Exception {} ({}) {f}", .{ exception, code, frame });
            @panic("Unhandled exception");
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
