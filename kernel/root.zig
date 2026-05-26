const std = @import("std");

pub const lib = @import("lib");

pub const arch = @import("arch/x86/root.zig");
pub const console = @import("console.zig");
pub const fs = @import("filesystem/root.zig");
pub const keyboard = @import("keyboard.zig");
const main = @import("main.zig");
pub const multiboot = @import("multiboot.zig");
pub const process = @import("process.zig");
pub const scheduler = @import("scheduler.zig");
pub const sparse_list = @import("sparse_list.zig");
pub const SparseList = sparse_list.SparseList;
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
    pub const PATH_MAX: usize = 256;
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

pub const KERNEL_CS: u16 = 1 << 3; // 0x8
pub const KERNEL_DS: u16 = 2 << 3; // 0x10
pub const USER_CS: u16 = (3 << 3) | 3; // 0x1B
pub const USER_DS: u16 = (4 << 3) | 3; // 0x23
pub const TSS: u16 = (5 << 3) | 3;

pub extern const kernel_end: usize;

pub fn kernelSize() usize {
    return kernel_end - KERNEL_BASE;
}

pub const panic = std.debug.FullPanic(kpanic);

pub fn kpanic(msg: []const u8, first_trace_addr: ?usize) noreturn {
    asm volatile ("cli");

    console.println("Panic at 0x{X}: {s}", .{ first_trace_addr orelse 0, msg });

    // const opt_trace: ?*std.builtin.StackTrace = @errorReturnTrace();
    // if (opt_trace) |trace| {
    //     console.println("Stack trace: ", .{});
    //     for (trace.instruction_addresses) |address| {
    //         console.println("0x{X}", .{address});
    //     }
    // }

    while (true) {
        asm volatile ("hlt");
    }
}
