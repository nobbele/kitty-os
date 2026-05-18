const std = @import("std");

pub const arch = @import("arch/x86/root.zig");
pub const console = @import("console.zig");
pub const fs = @import("filesystem.zig");
pub const keyboard = @import("keyboard.zig");
const main = @import("main.zig");
pub const multiboot = @import("multiboot.zig");
pub const process = @import("process.zig");
pub const scheduler = @import("scheduler.zig");
pub const shell = @import("shell.zig");
pub const syscall = @import("syscall.zig");

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

pub const KERNEL_CS: u8 = 1 << 3; // 0x8
pub const KERNEL_DS: u8 = 2 << 3; // 0x10
pub const USER_CS: u8 = (3 << 3) | 3; // 0x1B
pub const USER_DS: u8 = (4 << 3) | 3; // 0x23
pub const TSS: u8 = (5 << 3) | 3;

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
