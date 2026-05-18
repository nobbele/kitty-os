const root = @import("root");

const pmm = @import("pmm.zig");

pub const PAGE_DIRECTORY_COUNT: u32 = root.PAGE_SIZE / @sizeOf(u32);
pub const PAGE_TABLE_COUNT: u32 = root.PAGE_SIZE / @sizeOf(u32);

pub const Access = enum(u1) {
    kernel = 0,
    user = 1,
};

pub const PageDirectoryFlags = packed struct(u12) {
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

pub const PageDirEntry = packed struct(u32) {
    flags: PageDirectoryFlags,
    address_high: u20,
};

pub const PageTableFlags = packed struct(u12) {
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

pub const PageTableEntry = packed struct(u32) {
    flags: PageTableFlags,
    address_high: u20,
};
