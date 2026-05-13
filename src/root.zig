const std = @import("std");

const console = @import("console.zig");
const main = @import("main.zig");
const multiboot = @import("multiboot.zig");

comptime {
    @export(&multiboot.multiboot, .{ .name = "multiboot" });
    @export(&main.kmain, .{ .name = "kmain" });
}

pub const os = struct {
    pub const heap = struct {
        const PageAllocator = @import("PageAllocator.zig");
        pub const page_allocator: std.mem.Allocator = .{
            .ptr = undefined,
            .vtable = &PageAllocator.vtable,
        };
    };
};

pub const std_options: std.Options = .{
    .queryPageSize = queryPageSize,
};

fn queryPageSize() usize {
    return PAGE_SIZE;
}

pub const Ring = enum(u2) { kernel = 0, user = 3 };
pub const PAGE_SIZE: usize = 4096;
pub const KERNEL_BASE: usize = 0xC0000000;

pub extern const kernel_end: usize;

pub fn kernelSize() usize {
    return kernel_end - KERNEL_BASE;
}

pub const panic = std.debug.FullPanic(kpanic);

pub fn kpanic(msg: []const u8, first_trace_addr: ?usize) noreturn {
    _ = first_trace_addr;

    console.println("Panic! {s}", .{msg});

    while (true) {
        asm volatile ("hlt");
    }
}
