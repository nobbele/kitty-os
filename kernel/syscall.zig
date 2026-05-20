const std = @import("std");
const root = @import("root");

pub var syscall_handlers: std.AutoArrayHashMapUnmanaged(Syscall, *const SyscallHandler) = .empty;

pub fn registerSyscall(id: Syscall, h: SyscallHandler) !void {
    try syscall_handlers.put(std.heap.page_allocator, id, h);
}

pub const Syscall = enum(u8) { read, write, exec, sleep, _ };

pub const SyscallArgs = struct {
    args: [3]usize,
    frame: *root.arch.idt.InterruptFrame,

    pub fn get(self: SyscallArgs, comptime T: type, n: u8) T {
        if (@sizeOf(T) > @sizeOf(usize)) {
            @compileError("Arguments can't be sized larger than usize");
        }

        return switch (@typeInfo(T)) {
            .int, .comptime_int => @truncate(self.args[n]),
            .pointer => @ptrFromInt(self.args[n]),
            .@"enum" => @enumFromInt(self.args[n]),
            else => @compileError("Unsupported syscall arg type: " ++ @typeName(T)),
        };
    }
};

pub const SyscallResult = union(enum) {
    void,
    ok: usize,
    err: usize,
};

pub const SyscallHandler = fn (args: SyscallArgs) SyscallResult;
