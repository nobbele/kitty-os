const std = @import("std");

const console = @import("../console.zig");
const root = @import("../root.zig");
const pmm = @import("pmm.zig");

const PAGE_DIRECTORY_SIZE: u32 = 1024;
const PAGE_TABLE_SIZE: u32 = 1024;

const PageDirectoryFlags = packed struct(u12) {
    present: bool,
    writable: bool,
    access: enum(u1) { supervisor = 0, user = 1 },
    write_through: bool = false,
    cache_disabled: bool = false,
    accessed: bool = false,
    unused0: u1 = 0,
    large_page: bool = false,
    unused1: u4 = 0,

    pub fn toBacking(self: PageDirectoryFlags) u12 {
        return @as(u12, @bitCast(self));
    }
};

const PageTableFlags = packed struct(u12) {
    present: bool,
    writable: bool,
    access: enum(u1) { supervisor = 0, user = 1 },
    write_through: bool = false,
    cache_disabled: bool = false,
    accessed: bool = false,
    dirty: bool = false,
    reserved0: u1 = 0,
    global: bool = false,
    unused0: u3 = 0,

    pub fn toBacking(self: PageTableFlags) u12 {
        return @as(u12, @bitCast(self));
    }
};

pub fn init() !void {
    const allocator = std.heap.page_allocator;
    const page_dir = try allocator.alloc(u32, PAGE_DIRECTORY_SIZE);

    const total_pages = std.mem.alignForward(usize, pmm.total_pages, root.PAGE_SIZE);
    const page_dir_pages = total_pages / PAGE_DIRECTORY_SIZE;

    var address: usize = 0;

    console.println("[mmu] setting up {} pages", .{page_dir_pages});

    for (0..page_dir_pages) |dir_no| {
        const page_table = try allocator.alloc(u32, PAGE_TABLE_SIZE);

        for (0..PAGE_TABLE_SIZE) |page_no| {
            const table_flags: PageTableFlags = .{ .present = true, .writable = true, .access = .supervisor };
            page_table[page_no] = (@as(u32, address) * 0x1000) | table_flags.toBacking();
            address += 1;
        }

        const dir_flags: PageDirectoryFlags = .{ .present = true, .writable = true, .access = .supervisor };
        page_dir[dir_no] = @as(u32, @intFromPtr(page_table.ptr) & 0xFFFF_FF80) | dir_flags.toBacking();
    }

    for (page_dir_pages..PAGE_DIRECTORY_SIZE) |dir_no| page_dir[dir_no] = 2;

    loadPageDirectory(page_dir.ptr);
    enablePaging();
}

fn loadPageDirectory(addr: [*]u32) void {
    asm volatile (
        \\ mov %[addr], %%cr3
        :
        : [addr] "r" (addr),
    );
}

fn enablePaging() void {
    asm volatile (
        \\ mov %%cr0, %%eax
        \\ or $0x80000000, %%eax
        \\ mov %%eax, %%cr0
        ::: .{ .eax = true });
}
