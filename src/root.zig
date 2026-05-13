const std = @import("std");

const console = @import("console.zig");
const main = @import("main.zig");

pub const os = struct {
    pub const heap = struct {
        const PageAllocator = @import("PageAllocator.zig");
        pub const page_allocator: std.mem.Allocator = .{
            .ptr = undefined,
            .vtable = &PageAllocator.vtable,
        };
    };
};

pub const Ring = enum(u2) { kernel = 0, user = 3 };

var stack: [4 * 1024]u8 align(16) linksection(".bss") = undefined;

export fn _start() callconv(.naked) noreturn {
    asm volatile (
        \\ cli
        \\ movl %[stack_top], %%esp
        \\ movl %%esp, %%ebp
        \\ push %%ebx
        \\ call %[kmain:P]
        :
        : [stack_top] "i" (stack[stack.len..].ptr),
          [kmain] "X" (&main.kmain),
    );
}

pub const panic = std.debug.FullPanic(kpanic);

pub fn kpanic(msg: []const u8, first_trace_addr: ?usize) noreturn {
    _ = first_trace_addr;

    console.println("Panic! {s}", .{msg});

    while (true) {
        asm volatile ("hlt");
    }
}
