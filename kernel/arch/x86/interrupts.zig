const std = @import("std");
const builtin = @import("builtin");
const root = @import("root");
const console = root.console;
const syscall = root.syscall;

const idt = @import("idt.zig");
const mmu = @import("mmu.zig");
const pic = @import("pic.zig");
const vmm = @import("vmm.zig");

pub const IrqHandler = *const fn (frame: *idt.InterruptFrame) void;

var irq_handlers = std.mem.zeroes([pic.VEC_END - pic.VEC_START]?IrqHandler);

pub fn registerIrq(irq: u8, h: @typeInfo(IrqHandler).pointer.child) void {
    irq_handlers[irq] = h;
    pic.clearIrqMask(irq);
}

pub const Exception = enum(u8) {
    division_error,
    debug,
    nmi,
    breakpoint,
    overflow,
    bound_range_exceeded,
    invalid_opcode,
    device_not_available,
    double_fault,
    unused0,
    invalid_tss,
    segment_not_present,
    stack_segment_fault,
    general_protection_fault,
    page_fault,
    reserved0,
    x87_fp,
    alignment_check,
    machine_check,
    simd_fp,
    virtualization,
    control_protection,
    reserved1,
    hypervisor_injection,
    vmm_communication,
    security,
    reserved2,
    triple_fault,
    unused1,
    _,
};

pub fn handler(frame: *idt.InterruptFrame, vec: u8, code: u32) void {
    switch (vec) {
        0...31 => {
            const exception: Exception = @enumFromInt(vec);
            handleException(frame, exception, code);
        },
        pic.VEC_START...(pic.VEC_END - 1) => {
            const irq = vec - pic.VEC_START;
            if (irq_handlers[irq]) |h| {
                h(frame);
            } else if (comptime builtin.mode != .ReleaseFast) {
                std.debug.panic("No handler registered for IRQ {}", .{irq});
            }
            pic.sendEoi(vec);
        },
        0x80 => dispatchSyscall(frame),
        else => {
            console.println("Unknown IRQ: 0x{X} ({}) {}", .{ vec, code, frame });
        },
    }
}

const PageFaultErrorCode = packed struct(u32) {
    present: bool,
    write: bool,
    user: bool,
    reserved_write: bool,
    instruction_fetch: bool,
    protection_key: bool,
    shadow_stack: bool,
    reserved0: u8,
    sgx: bool,
    reserved1: u16,
};

fn handleException(frame: *idt.InterruptFrame, exception: Exception, code: u32) void {
    switch (exception) {
        .breakpoint => {
            console.println("Hit a {s} breakpoint:", .{if (frame.fromUser()) "user" else "kernel"});
            console.println("{f}", .{frame});
            @panic("breakpoint");
        },
        .page_fault => {
            const err: PageFaultErrorCode = @bitCast(code);
            const fault_addr = asm volatile ("mov %%cr2, %[cr2]"
                : [cr2] "=r" (-> usize),
            );

            if (fault_addr >= root.KERNEL_BASE and !err.present) {
                console.println("[int] Copying kernel mapping for {}", .{fault_addr});
                const pdi = fault_addr >> 22;
                const kernel_pde = vmm.kernel_entries[pdi];
                if (kernel_pde.flags.present) {
                    const cr3 = asm volatile ("mov %%cr3, %[cr3]"
                        : [cr3] "=r" (-> usize),
                    );
                    const pd: [*]mmu.PageDirEntry = @ptrFromInt(root.KERNEL_BASE + cr3);
                    pd[pdi] = kernel_pde;
                    return; // resume execution, no invlpg needed
                }
            }

            std.debug.panic("Page fault at 0x{x} ({s}): {}", .{
                fault_addr,
                if (err.user) "user" else "kernel",
                err,
            });
        },
        else => {
            console.println("Exception {} ({}) {f}", .{ exception, code, frame });
            @panic("Unhandled exception");
        },
    }
}

fn dispatchSyscall(frame: *idt.InterruptFrame) void {
    const args = syscall.SyscallArgs{
        .args = .{
            frame.ebx, frame.ecx, frame.edx,
            // frame.esi, frame.edi, frame.ebp,
        },
        .frame = frame,
    };

    const id: syscall.Syscall = @enumFromInt(frame.eax);
    const result: syscall.SyscallResult = if (syscall.syscall_handlers.get(id)) |h|
        h(args)
    else blk: {
        console.println("Unimplemented syscall {}", .{id});
        break :blk .{ .err = 38 };
    };

    // TODO don't set these unnecessarily?
    // Leave eax unchanged when void.
    // Put error in a specific user-accessible memory location like errno.
    frame.eax = switch (result) {
        .ok => |v| v,
        else => 0,
    };
    frame.edx = switch (result) {
        .err => |e| e,
        else => 0,
    };
}
