const std = @import("std");
const root = @import("root");
const console = root.console;

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

pub const InterruptFrame = extern struct {
    // pushed manually by stub:
    eax: usize,
    ebx: usize,
    ecx: usize,
    edx: usize,
    ebp: usize,
    esi: usize,
    edi: usize,
    // CPU pushed these:
    eip: usize,
    cs: usize,
    flags: usize,

    // only present on privilege change (ring 3 → ring 0):
    esp: usize,
    ss: usize,

    pub fn fromUser(self: *InterruptFrame) bool {
        return self.cs == root.USER_CS;
    }

    pub fn format(
        self: *InterruptFrame,
        writer: *std.Io.Writer,
    ) !void {
        try writer.print(
            \\----------------------
            \\| eax   | 0x{[eax]X:0>8} |
            \\| ebx   | 0x{[ebx]X:0>8} |
            \\| ecx   | 0x{[ecx]X:0>8} |
            \\| edx   | 0x{[edx]X:0>8} |
            \\| ebp   | 0x{[ebp]X:0>8} |
            \\| esi   | 0x{[esi]X:0>8} |
            \\| edi   | 0x{[edi]X:0>8} |
            \\|--------------------|
            \\| ip    | 0x{[eip]X:0>8} |
            \\| cs    | 0x{[cs]X:0>8} |
            \\| flags | 0x{[flags]X:0>8} |
            \\|--------------------|
            \\| esp | 0x{[esp]X:0>8} |
            \\| ss | 0x{[ss]X:0>8} |
            \\----------------------
        , self.*);
    }
};

export fn handler_trampoline(frame: *InterruptFrame, vec: u8, code: u32) callconv(.c) void {
    interrupts.handler(frame, vec, code);
}

inline fn make_stub(comptime vec: u8, comptime has_err: bool) *const anyopaque {
    const S = struct {
        fn handler() callconv(.naked) void {
            // already on stack: flags, cs, ip.

            const err = if (has_err) asm volatile ("pop %[ret]"
                : [ret] "={esi}" (-> u32),
            ) else 0;

            const frame = asm volatile (
                \\ push %%edi
                \\ push %%esi
                \\ push %%ebp
                \\ push %%edx
                \\ push %%ecx
                \\ push %%ebx
                \\ push %%eax
                : [ret] "={esp}" (-> usize),
            );

            asm volatile (
                \\ pushl %[err]
                \\ pushl %[vec]
                \\ pushl %[frame]
                \\ call handler_trampoline
                \\ addl $12, %esp
                \\ pop %%eax
                \\ pop %%ebx
                \\ pop %%ecx
                \\ pop %%edx
                \\ pop %%ebp
                \\ pop %%esi
                \\ pop %%edi
                \\ iret
                :
                : [err] "r" (err),
                  [vec] "i" (vec),
                  [frame] "r" (frame),
            );
        }
    };
    return @ptrCast(&S.handler);
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

    idt[0x3].ring = .user;
    idt[0x80].ring = .user;

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
