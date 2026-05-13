const std = @import("std");

const pmm = @import("arch/pmm.zig");
const console = @import("console.zig");

pub const vtable: std.mem.Allocator.VTable = .{
    .alloc = alloc,
    .resize = std.mem.Allocator.noResize,
    .remap = std.mem.Allocator.noRemap,
    .free = free,
};

const Header = struct {
    size: usize,
};

fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    _ = ctx;
    _ = ret_addr;
    _ = alignment;
    const addr = pmm.alloc(len);
    if (addr == null) {
        return null;
    }

    return @ptrFromInt(addr.?);
}

fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
    _ = ctx;
    _ = ret_addr;
    _ = alignment;
    const addr = @intFromPtr(memory.ptr);
    pmm.free(addr, memory.len);
}
