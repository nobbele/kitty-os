const std = @import("std");

const console = @import("../../console.zig");
const root = @import("../../root.zig");
const pmm = @import("pmm.zig");

const PAGE_DIRECTORY_SIZE: u32 = root.PAGE_SIZE / @sizeOf(u32);
const PAGE_TABLE_SIZE: u32 = root.PAGE_SIZE / @sizeOf(u32);

pub const Access = enum(u1) {
    kernel = 0,
    user = 1,
};

const PageDirectoryFlags = packed struct(u12) {
    present: bool,
    writable: bool,
    access: Access,
    write_through: bool = false,
    cache_disabled: bool = false,
    accessed: bool = false,
    unused0: u1 = 0,
    large_page: bool = false,
    unused1: u4 = 0,
};

const PageDirectoryEntry = packed struct(u32) {
    flags: PageDirectoryFlags,
    address_high: u20,
};

const PageTableFlags = packed struct(u12) {
    present: bool,
    writable: bool,
    access: Access,
    write_through: bool = false,
    cache_disabled: bool = false,
    accessed: bool = false,
    dirty: bool = false,
    reserved0: u1 = 0,
    global: bool = false,
    unused0: u3 = 0,
};

const PageTableEntry = packed struct(u32) {
    flags: PageTableFlags,
    address_high: u20,
};

var dir_phys: usize = undefined;
var dir_entries: [*]PageDirectoryEntry = undefined;

pub fn init() !void {
    dir_phys = pmm.alloc(PAGE_DIRECTORY_SIZE * @sizeOf(u32)) orelse return error.OutOfMemory;
    dir_entries = @ptrFromInt(root.KERNEL_BASE + dir_phys);

    @memset(dir_entries[0..PAGE_DIRECTORY_SIZE], @bitCast(@as(u32, 0)));

    // Page-aligned kernel size.
    const size_in_pages = std.mem.alignForward(usize, root.kernelSize(), root.PAGE_SIZE);
    console.println("[mmu] Kernel Size: {Bi:.1}", .{size_in_pages});

    const page_count = size_in_pages / root.PAGE_SIZE;

    for (0..page_count) |page_no| {
        const virt = root.KERNEL_BASE + (page_no * root.PAGE_SIZE);
        const phys = 0x0 + (page_no * root.PAGE_SIZE);
        try map(virt, phys, .{});
    }

    try map(0xC03FF000, 0x000B8000, .{});

    console.println("[mmu] Loading new page tables", .{});
    reloadPages();
}

const MappingError = error{
    UnalignedAddress,
};

pub const MappingOptions = struct {
    access: Access = .kernel,
    writable: bool = true,
};

pub fn map(virt: usize, phys: usize, opts: MappingOptions) !void {
    if (!std.mem.isAligned(virt, root.PAGE_SIZE) or !std.mem.isAligned(phys, root.PAGE_SIZE))
        return MappingError.UnalignedAddress;

    const table_entry = &dir_entries[virt >> 22];

    if (!table_entry.flags.present) {
        const table_phys = pmm.alloc(PAGE_TABLE_SIZE * @sizeOf(u32)) orelse return error.OutOfMemory;
        const table_entries: [*]PageTableEntry = @ptrFromInt(root.KERNEL_BASE + table_phys);

        @memset(table_entries[0..PAGE_TABLE_SIZE], @bitCast(@as(u32, 0)));

        table_entry.address_high = @truncate(table_phys >> 12);
        table_entry.flags = .{
            .present = true,
            .writable = opts.writable,
            .access = opts.access,
        };
    }

    const table_phys = table_entry.address_high << 12;
    const table: [*]PageTableEntry = @ptrFromInt(root.KERNEL_BASE + table_phys);
    const page_entry = &table[(virt >> 12) & 0x3FF];

    if (page_entry.flags.present)
        @panic("Page for virtual VGA address is occupied");

    page_entry.flags = .{ .present = true, .writable = opts.writable, .access = opts.access };
    page_entry.address_high = @truncate(phys >> 12);
}

pub fn virtualToPhysical(virt: usize) ?usize {
    const virt_table = (virt >> 22) & 0x3FF;
    const virt_page = (virt >> 12) & 0x3FF;
    const virt_offset = virt & 0x3FF;

    const dir = dir_entries[virt_table];
    if (!dir.flags.present) return null;

    const table_phys = dir.address_high << 12;
    const table_entries: [*]PageTableEntry = @ptrFromInt(root.KERNEL_BASE + table_phys);
    const table = table_entries[virt_page];
    if (!table.flags.present) return null;

    const page_phys = table.address_high << 12;
    return page_phys + virt_offset;
}

fn reloadPages() void {
    asm volatile (
        \\ mov %[addr], %%cr3
        :
        : [addr] "r" (dir_phys),
    );
}
