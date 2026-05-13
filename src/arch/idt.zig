const std = @import("std");

const console = @import("../console.zig");
const root = @import("../root.zig");
const interrupts = @import("interrupts.zig");

const SegmentSelector = packed struct(u16) {
    // Requested ring to use
    ring: root.Ring,
    /// Specifies which descriptor table to use (GDT or current LDT).
    desc: enum(u1) { global = 0, local = 1 },
    // Index into the descriptor table.
    index: u13,
};

const GateType = enum(u4) {
    task = 0x5,
    // interrupt16 = 0x6,
    // trap16 = 0x7,
    interrupt32 = 0xE,
    trap32 = 0xF,
};

const IDTR = packed struct(u48) { size: u16, offset: usize };
const IDTGate = packed struct(u64) {
    offset_low: u16,
    selector: SegmentSelector,
    reserved0: u8 = 0,
    gate_type: GateType,
    reserved1: u1 = 0,
    ring: root.Ring,
    present: u1 = 1,
    offset_high: u16,

    pub fn init(self: *IDTGate, offset: u32) void {
        self.* = .{
            .offset_low = @truncate(offset),
            .offset_high = @truncate(offset >> 16),
            .selector = .{
                .ring = .kernel,
                .desc = .global,
                .index = 1,
            },
            .ring = .kernel,
            .gate_type = .interrupt32,
        };
    }
};

const InterruptStackFrame = extern struct {
    ip: usize,
    cs: usize,
    flags: usize,
};

inline fn make_stub(comptime vec: u8, comptime has_err: bool) *const anyopaque {
    if (has_err) {
        const S = struct {
            fn handler(frame: *InterruptStackFrame, code: usize) callconv(.{ .x86_interrupt = .{} }) void {
                const cast: *InterruptStackFrame = @ptrCast(frame);
                _ = cast; // autofix
                interrupts.handler(vec, code);
            }
        };
        return @ptrCast(&S.handler);
    } else {
        const S = struct {
            fn handler(frame: *InterruptStackFrame) callconv(.{ .x86_interrupt = .{} }) void {
                const cast: *InterruptStackFrame = @ptrCast(frame);
                _ = cast; // autofix
                interrupts.handler(vec, 0);
            }
        };
        return @ptrCast(&S.handler);
    }
}

pub const stubs: [256]*const anyopaque = blk: {
    var t: [256]*const anyopaque = undefined;
    // @setEvalBranchQuota(10_000);
    for (0..256) |i| {
        const has_err = switch (i) {
            8, 10, 11, 12, 13, 14, 17, 21, 29, 30 => true,
            else => false,
        };
        t[i] = make_stub(@intCast(i), has_err);
    }
    break :blk t;
};

var idt: [256]IDTGate align(16) linksection(".bss") = undefined;

pub fn init() !void {
    for (0..256) |vec| {
        idt[vec].init(@intFromPtr(stubs[vec]));
    }

    loadIDT(.{
        .offset = @intFromPtr(&idt),
        .size = @intCast(@sizeOf(IDTGate) * idt.len - 1),
    });
}

pub fn loadIDT(idtr: IDTR) void {
    asm volatile (
        \\ lidt (%[idtr])
        :
        : [idtr] "r" (&idtr),
    );
}
