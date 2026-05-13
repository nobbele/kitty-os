const std = @import("std");

const console = @import("../console.zig");
const pmm = @import("pmm.zig");

const PAGE_DIRECTORY_SIZE = 1024;
const PAGE_TABLE_SIZE = 1024;

fn loadPageDirectory(addr: [*]u32) void {
    asm volatile (
        \\ mov %[addr], %%cr3
        :
        : [addr] "{eax}" (addr),
    );
}

fn enablePaging() void {
    asm volatile (
        \\ mov %%cr0, %%eax
        \\ or $0x80000000, %%eax
        \\ mov %%eax, %%cr0
        ::: .{ .eax = true });
}

pub fn init() !void {
    const allocator = std.heap.page_allocator;
    const page_dir = try allocator.alloc(u32, PAGE_DIRECTORY_SIZE);

    const total_pages = std.mem.alignForward(usize, pmm.total_pages, 4096);
    const page_dir_pages = total_pages / PAGE_DIRECTORY_SIZE;

    var address: usize = 0;

    console.println("[mmu] setting up {} pages", .{page_dir_pages});

    for (0..page_dir_pages) |dir_no| {
        const page_table = try allocator.alloc(u32, PAGE_TABLE_SIZE);

        for (0..PAGE_TABLE_SIZE) |page_no| {
            page_table[page_no] = (@as(u32, address) * 0x1000) | 3;
            address += 1;
        }

        page_dir[dir_no] = @as(u32, @intFromPtr(page_table.ptr)) | 3;
    }

    for (page_dir_pages..PAGE_DIRECTORY_SIZE) |dir_no| page_dir[dir_no] = 2;

    loadPageDirectory(page_dir.ptr);
    enablePaging();
}
