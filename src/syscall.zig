const std = @import("std");

pub var syscall_handlers: std.AutoArrayHashMapUnmanaged(Syscall, *const SyscallHandler) = .empty;

pub fn registerSyscall(id: Syscall, h: SyscallHandler) void {
    syscall_handlers.put(std.heap.page_allocator, id, h);
}

pub const Syscall = enum(u8) { write = 1, _ };

pub const SyscallArgs = struct {
    args: [3]usize,

    pub fn get(self: SyscallArgs, comptime T: type, n: u8) T {
        return switch (@typeInfo(T)) {
            .int, .comptime_int => @intCast(self.args[n]),
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
