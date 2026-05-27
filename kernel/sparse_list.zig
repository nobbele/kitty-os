const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn SparseList(comptime T: type) type {
    return struct {
        pub const Self = @This();

        array: std.ArrayList(?T),

        pub const empty: Self = .{
            .array = .empty,
        };

        fn findSlot(self: *Self, gpa: Allocator) !usize {
            for (self.array.items, 0..) |item, i| {
                if (item == null) return i;
            }

            try self.array.append(gpa, null);
            return self.array.items.len - 1;
        }

        pub fn add(self: *Self, gpa: Allocator, item: T) !usize {
            const slot = try self.findSlot(gpa);
            self.array.items[slot] = item;
            return slot;
        }

        pub fn insert(self: *Self, gpa: Allocator, i: usize, item: T) !void {
            if (i >= self.array.items.len)
                try self.array.appendNTimes(gpa, null, i - self.array.items.len + 1);
            try self.array.insert(gpa, i, item);
        }
    };
}
