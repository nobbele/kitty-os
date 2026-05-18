const std = @import("std");
const root = @import("root");
const pmm = root.arch.pmm;
const vmm = root.arch.vmm;
const console = root.console;

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
    std.debug.assert(alignment.toByteUnits() <= root.PAGE_SIZE);

    const phys = pmm.alloc(len) orelse return null;

    return @ptrFromInt(root.KERNEL_BASE + phys);
}

fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
    _ = ctx;
    _ = ret_addr;
    _ = alignment;
    const addr = @intFromPtr(memory.ptr) - root.KERNEL_BASE;
    pmm.free(addr, memory.len);
}
