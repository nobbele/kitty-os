const std = @import("std");

const console = @import("../console.zig");
const root = @import("../root.zig");

const SegmentAccess = packed struct(u8) {
    const Self = @This();

    /// The CPU will set it when the segment is accessed unless set to 1 in advance.
    /// This means that in case the GDT descriptor is stored in read only pages and this bit is set to 0,
    /// the CPU trying to set this bit will trigger a page fault.
    ///
    /// Best left set to 1 unless otherwise needed.
    accessed: bool = false,
    /// For code segments: Readable bit.
    /// - If false, read access for this segment is not allowed.
    /// - If true, read access is allowed.
    /// - Write access is never allowed for code segments.
    ///
    /// For data segments: Writeable bit.
    /// - If false, write access for this segment is not allowed.
    /// - If true, write access is allowed.
    /// - Read access is always allowed for data segments.
    rw: bool = true,
    /// For data selectors: Direction bit.
    /// - If false, the segment grows up.
    /// - If true, the segment grows down, ie. the Offset has to be greater than the Limit.
    ///
    /// For code selectors: Conforming bit.
    /// - If false, code in this segment can only be executed from the ring set in DPL.
    /// - If true, code in this segment can be executed from an equal or lower privilege level.
    /// For example, code in ring 3 can far-jump to conforming code in a ring 2 segment. The DPL field represent the highest privilege level that is allowed to execute the segment. For example, code in ring 0 cannot far-jump to a conforming code segment where DPL is 2, while code in ring 2 and 3 can. Note that the privilege level remains the same, ie. a far-jump from ring 3 to a segment with a DPL of 2 remains in ring 3 after the jump.
    dc: bool,
    /// - If false, the descriptor defines a data segment.
    /// - If true, it defines a code segment which can be executed from.
    exec: bool,
    /// - If false, the descriptor defines a system segment (eg. a Task State Segment).
    /// - If true, it defines a code or data segment.
    desc_type: bool = true,
    /// Contains the CPU Privilege level of the segment.
    ring: root.Ring,
    // Must be true for any valid segment.
    present: bool = true,

    pub const kernel_code: Self = .{
        .ring = .kernel,
        .exec = true,
        .dc = false,
    };
    pub const kernel_data: Self = .{
        .ring = .kernel,
        .exec = false,
        .dc = false,
    };
    pub const user_code: Self = .{
        .ring = .user,
        .exec = true,
        .dc = false,
    };
    pub const user_data: Self = .{
        .ring = .user,
        .exec = false,
        .dc = false,
    };
};

const Flags = packed struct(u4) {
    reserved: u1 = 0,
    //  If true, the descriptor defines a 64-bit code segment
    long_mode: bool = false,
    size: enum(u1) { bit16 = 0, bit32 = 1 } = .bit32,
    // Indicates the size the Limit value is scaled by.
    // - If .byte (0), the Limit is in 1 Byte blocks.
    // - If .page (1), the Limit is in 4 KiB blocks.
    granularity: enum(u1) { byte = 0, page = 1 } = .page,
};

test "segment access" {
    const expect = std.testing.expect;
    try expect(@as(u8, @bitCast(SegmentAccess.kernel_code)) == 0x9A);
    try expect(@as(u8, @bitCast(SegmentAccess.kernel_data)) == 0x92);
    try expect(@as(u8, @bitCast(SegmentAccess.user_code)) == 0xFA);
    try expect(@as(u8, @bitCast(SegmentAccess.user_data)) == 0xF2);
}

const GDTR = packed struct(u48) { size: u16, offset: usize };
const GDTEntry = packed struct(u64) {
    limit_low: u16,
    base_low: u24,
    access: u8,
    limit_high: u4,
    flags: u4,
    base_high: u8,

    pub fn init(self: *GDTEntry, base: u32, limit: u20, access: SegmentAccess) void {
        self.* = .{
            .base_low = @truncate(base),
            .base_high = @truncate(base >> 24),
            .limit_low = @truncate(limit),
            .limit_high = @truncate(limit >> 16),
            .flags = @bitCast(Flags{}),
            .access = @bitCast(access),
        };
    }

    pub fn init_flat(self: *GDTEntry, access: SegmentAccess) void {
        self.init(0, 0xFFFFF, access);
    }

    pub fn init_null(self: *GDTEntry) void {
        self.* = @bitCast(@as(u64, 0));
    }
};

var gdt: [3]GDTEntry align(16) linksection(".bss") = undefined;

pub fn init() !void {
    gdt[0].init_null();

    // First 3 bits in the segment selector are ignored
    gdt[1].init_flat(.kernel_code); // 0x8
    gdt[2].init_flat(.kernel_data); // 0x10

    loadGDT(.{
        .offset = @intFromPtr(&gdt),
        .size = @intCast(@sizeOf(GDTEntry) * gdt.len - 1),
    });

    console.println("[gdt] Kernel code = 0x08", .{});
    console.println("[gdt] Kernel data = 0x10", .{});
}

pub fn loadGDT(gdtr: GDTR) void {
    asm volatile (
        \\ lgdt (%[gdtr])
        \\ ljmp $0x08, $reload_cs
        \\ reload_cs:
        \\ mov $0x10, %ax
        \\ mov %ax, %ds
        \\ mov %ax, %es
        \\ mov %ax, %fs
        \\ mov %ax, %gs
        \\ mov %ax, %ss
        :
        : [gdtr] "r" (&gdtr),
    );
}
