const std = @import("std");

const arch = @import("arch.zig");
const console = @import("console.zig");
const multiboot = @import("multiboot.zig");
const shell = @import("shell.zig");

pub export fn kmain(multiboot_info_address: usize) noreturn {
    console.init();

    console.println("[multiboot] init", .{});
    multiboot.init(multiboot_info_address);

    arch.init() catch unreachable;

    const t = std.heap.page_allocator.create(u8) catch unreachable;
    console.println("{*}", .{t});

    for (multiboot.modules) |module| {
        console.println("{x} {Bi:.1}", .{ module.data, module.data.len });

        const f: *const fn () void = @ptrCast(module.data);
        console.println("Jumping!", .{});
        f();
    }

    console.println("[shell] start", .{});
    shell.run();
}
