const std = @import("std");
const root = @import("root");
const console = root.console;
const multiboot = root.multiboot;

const Map = struct { address: usize, size: usize };

const BitmapUnit = u8;
var bitmap: []allowzero volatile BitmapUnit = undefined;

pub var total_size: usize = 0;
pub var total_pages: usize = 0;
pub var pages_in_use: usize = 0;

var bitmap_size: usize = 0;
var bitmap_size_pages: usize = 0;

fn initBitmap(bitmap_address: usize, memory_maps: []Map) void {
    bitmap = @as([*]allowzero volatile BitmapUnit, @ptrFromInt(bitmap_address))[0..bitmap_size];

    var address: usize = 0;

    for (bitmap) |*bitmap_unit| {
        var unit: BitmapUnit = 0;

        for (0..@bitSizeOf(BitmapUnit)) |bit| {
            const address_free = for (memory_maps) |map| {
                if (address >= map.address and address <= map.address + map.size) {
                    break true;
                }
            } else false;

            const mask: u8 = @intCast(@as(u16, 1) << @as(u4, @intCast(bit)));
            if (!address_free) {
                unit |= mask;
            }

            address += root.PAGE_SIZE;
        }

        bitmap_unit.* = unit;
    }

    var satisfied_pages: usize = 0;

    // Allocate the pages used for storing the bitmap itself.
    blk: for (bitmap) |*unit| {
        for (0..@bitSizeOf(BitmapUnit)) |bit| {
            // We have allocated the required number of pages, we can safely return the buffer now.
            if (satisfied_pages == bitmap_size_pages) {
                pages_in_use += bitmap_size_pages;
                break :blk;
            }

            const mask: u8 = @intCast(@as(u16, 1) << @as(u4, @intCast(bit)));
            if ((unit.* & mask) == 0) {
                // We found a free page
                satisfied_pages += 1;
                unit.* |= mask;
            } else {
                // This should never happen
                std.debug.panic("[pmm,bitmap] found allocated page while trying to allocate bitmap", .{});
                return;
            }
        }
    }
}

// https://github.com/limine-bootloader/limine/blob/886523359c85aa10691e6b82229c91f31f21a04f/common/lib/misc.h#L66
fn divRoundUp(a: usize, b: usize) usize {
    return (a + (b - 1)) / b;
}

pub fn init(max_memory_address: usize, entries: []multiboot.MultibootMemoryMapEntry) void {
    var buffer: [1024]u8 align(16) = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const memory_maps = allocator.alloc(Map, entries.len) catch unreachable;
    defer allocator.free(memory_maps);

    var number_of_maps: usize = 0;
    var bitmap_map: ?Map = null;

    for (entries) |*entry| {
        // A value of 1 indicates available RAM
        if (entry.type == 1 and entry.address <= max_memory_address) {
            const size: usize = @intCast(entry.length);
            const map = Map{ .address = @intCast(entry.address), .size = size };

            memory_maps[number_of_maps] = map;
            number_of_maps += 1;
            total_size += size;

            total_pages = total_size / root.PAGE_SIZE;
            bitmap_size = divRoundUp(total_pages, @bitSizeOf(BitmapUnit));
            bitmap_size_pages = divRoundUp(bitmap_size, root.PAGE_SIZE);

            if (bitmap_map == null and bitmap_size <= size) {
                bitmap_map = map;
            }
        }
    }

    console.serialPrintln("{any}", .{memory_maps});

    if (bitmap_map == null) {
        @panic("[pmm] not enough memory to initialize bitmap");
    }

    console.serialPrintln("[pmm] Available memory: {Bi:.1}", .{total_size});
    console.serialPrintln("[pmm] Reserved for bitmap: {Bi:.1}", .{bitmap_size});

    console.serialPrintln("[pmm,bitmap] init", .{});
    initBitmap(0xC0000000 + bitmap_map.?.address, memory_maps[0..number_of_maps]);

    // low 1MB: BIOS, IVT, VGA
    // kernel image: 1MB to kernel_end
    const kernel_end_phys = 0x100000 + root.kernelSize();
    const kernel_end_page = divRoundUp(kernel_end_phys, root.PAGE_SIZE);
    for (0..kernel_end_page) |p| markUsed(p);
    pages_in_use += kernel_end_page;

    for (multiboot.modules[0..multiboot.modulesCount]) |mod| {
        const start_page = std.mem.alignBackward(usize, mod.data_addr, root.PAGE_SIZE) / root.PAGE_SIZE;
        const page_count = divRoundUp(mod.data_len, root.PAGE_SIZE);
        for (start_page..start_page + page_count) |p| markUsed(p);
        pages_in_use += page_count;
    }

    const vga_start = std.mem.alignBackward(usize, 0x3FF000, root.PAGE_SIZE) / root.PAGE_SIZE;
    for (vga_start..vga_start + divRoundUp(root.console.VGA_SIZE, root.PAGE_SIZE)) |page| {
        markUsed(page);
        pages_in_use += 1;
    }
}

fn markUsed(page: usize) void {
    const unit = page / @bitSizeOf(BitmapUnit);
    const bit = page % @bitSizeOf(BitmapUnit);
    bitmap[unit] |= @as(u8, @intCast(@as(u16, 1) << @as(u4, @intCast(bit))));
}

fn isAddressUsed(addr: usize) bool {
    const aligned_addr = std.mem.alignBackward(usize, addr, root.PAGE_SIZE);
    const page = aligned_addr / root.PAGE_SIZE;
    return isUsed(page);
}

fn isUsed(page: usize) bool {
    const unit = page / @bitSizeOf(BitmapUnit);
    const bit = page % @bitSizeOf(BitmapUnit);
    return (bitmap[unit] & @as(u8, @intCast(@as(u16, 1) << @as(u4, @intCast(bit))))) != 0;
}

pub fn alloc(size: usize) !usize {
    const req_pages = divRoundUp(size, root.PAGE_SIZE);

    var run_start: usize = 0;
    var run_len: usize = 0;
    var page: usize = 0;

    outer: for (bitmap) |_| {
        for (0..@bitSizeOf(BitmapUnit)) |_| {
            if (page >= total_pages) break :outer;

            const unit = page / @bitSizeOf(BitmapUnit);
            const bit: u3 = @intCast(page % @bitSizeOf(BitmapUnit));
            const mask = @as(BitmapUnit, 1) << bit;

            if ((bitmap[unit] & mask) == 0) {
                if (run_len == 0) run_start = page;
                run_len += 1;
                if (run_len == req_pages) {
                    // Found a run — mark all pages used
                    for (run_start..run_start + req_pages) |p| markUsed(p);
                    pages_in_use += req_pages;
                    return run_start * root.PAGE_SIZE;
                }
            } else {
                run_len = 0;
            }

            page += 1;
        }
    }

    console.serialPrintln("[pmm] Unable to allocate {Bi:.1}", .{size});
    return error.OutOfMemory;
}

pub fn free(address: usize, size: usize) !void {
    const start_page = address / root.PAGE_SIZE;
    const page_count = divRoundUp(size, root.PAGE_SIZE);

    if (page_count >= bitmap.len * @bitSizeOf(BitmapUnit)) {
        console.serialPrintln("[pmm] Failed free {Bi:.1} bytes at 0x{X:.1}", .{ size, address });
        return error.OutOfRange;
    }

    for (start_page..start_page + page_count) |page| {
        const unit = page / @bitSizeOf(BitmapUnit);
        const bit = page % @bitSizeOf(BitmapUnit);
        const mask = (@as(u8, @intCast(@as(u16, 1) << @as(u4, @intCast(bit)))));
        bitmap[unit] &= ~mask;
    }
}
