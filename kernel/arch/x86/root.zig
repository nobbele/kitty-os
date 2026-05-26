const std = @import("std");
const root = @import("root");
const console = root.console;
const multiboot = root.multiboot;

pub const gdt = @import("gdt.zig");
pub const idt = @import("idt.zig");
pub const pic = @import("pic.zig");
pub const pmm = @import("pmm.zig");
pub const port = @import("port.zig");
pub const process = @import("process.zig");
pub const ps2 = @import("ps2.zig");
pub const timer = @import("timer.zig");
pub const vmm = @import("vmm.zig");

pub const EFlags = packed struct(u32) {
    carry: bool = false,
    _0: u1 = 0,
    parity: bool = false,
    _1: u1 = 0,
    aux: bool = false,
    _2: u1 = 0,
    zero: bool = false,
    sign: bool = false,
    trap: bool = false,
    interrupt: bool = false,
    direction: bool = false,
    overflow: bool = false,
    ring: u2 = 0,
    nested_task: bool = false,
    _3: u1 = 0,
    @"resume": bool = false,
    vm86: bool = false,
    alignment: bool = false,
    virt_int: bool = false,
    virt_int_pending: bool = false,
    cpuid: bool = false,
    _4: u10 = 0,

    pub fn format(
        self: *const EFlags,
        writer: *std.Io.Writer,
    ) !void {
        try writer.print("EFLAGS(", .{});

        var any = false;
        inline for (.{
            .{ "CF", self.carry },
            .{ "PF", self.parity },
            .{ "AF", self.aux },
            .{ "ZF", self.zero },
            .{ "SF", self.sign },
            .{ "TF", self.trap },
            .{ "IF", self.interrupt },
            .{ "DF", self.direction },
            .{ "OF", self.overflow },
            .{ "NT", self.nested_task },
            .{ "RF", self.@"resume" },
            .{ "VM", self.vm86 },
            .{ "AC", self.alignment },
            .{ "VIF", self.virt_int },
            .{ "VIP", self.virt_int_pending },
            .{ "ID", self.cpuid },
        }) |f| {
            if (f[1]) {
                if (any) try writer.print("|", .{});
                try writer.print("{s}", .{f[0]});
                any = true;
            }
        }

        try writer.print(" IOPL={d})", .{self.ring});
    }
};

pub fn init() !void {
    console.println("[pmm] init", .{});
    pmm.init(multiboot.memoryUpper * 1024, multiboot.entries);

    console.println("[vmm] init", .{});
    vmm.init() catch unreachable;

    console.println("[gdt] init", .{});
    gdt.init() catch unreachable;

    console.println("[idt] init", .{});
    idt.init() catch unreachable;

    console.println("[pic] init", .{});
    pic.init();

    console.println("[timer] init", .{});
    timer.init();

    asm volatile ("sti");

    console.println("[ps2] init", .{});
    ps2.init();
}
