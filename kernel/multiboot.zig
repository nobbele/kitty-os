// https://www.gnu.org/software/grub/manual/multiboot2/multiboot.html
const root = @import("root.zig");
const console = root.console;

const MultibootHeader = extern struct {
    magic: u32 align(8),
    architecture: u32 align(1),
    header_length: u32 align(1),
    checksum: u32 align(1),
};

const MAGIC = 0xE85250D6;
const ARCHITECTURE = 0; // i386 (protected mode)

const MultibootFramebufferRequestTag = extern struct {
    type: u16 align(1) = 5,
    flags: u16 align(1) = 0,
    size: u32 align(1) = @sizeOf(@This()),
    width: u32 align(1) = 0,
    height: u32 align(1) = 0,
    depth: u32 align(1) = 0,
};

const MultibootHeaderEndTag = extern struct {
    type: u16 align(1) = 0,
    flags: u16 align(1) = 0,
    size: u32 align(1) = @sizeOf(@This()),
};

const MultibootRequest = extern struct {
    header: MultibootHeader,
    fb_tag: MultibootFramebufferRequestTag,
    end_tag: MultibootHeaderEndTag,
};

pub const multiboot: MultibootRequest align(8) linksection(".multiboot") = .{
    .header = .{
        .magic = MAGIC,
        .architecture = ARCHITECTURE,
        .header_length = @sizeOf(MultibootRequest),
        .checksum = 0x100000000 - (MAGIC + ARCHITECTURE + @sizeOf(MultibootRequest)),
    },
    .fb_tag = .{},
    .end_tag = .{},
};

const MultibootTagType = enum(u32) {
    end = 0,
    cmdline = 1,
    bootloaderName = 2,
    module = 3,
    basicMemInfo = 4,
    mmap = 6,
    framebuffer = 8,
    _,
};

const MultibootEntry = extern struct {
    type: MultibootTagType align(1),
    size: u32 align(1),
};

const TAG_SIZE = @sizeOf(MultibootEntry);

pub const MultibootMemoryMapEntry = extern struct {
    address: u64 align(1),
    length: u64 align(1),
    type: u32 align(1),
    reserved: u32 align(1),
};

pub const MultibootModuleEntry = struct {
    data_addr: usize,
    data_len: usize,
    str_addr: usize,
};

const MultibootFramebufferEntry = extern struct {
    addr: u64 align(1),
    pitch: u32 align(1),
    width: u32 align(1),
    height: u32 align(1),
    bpp: u8 align(1),
    fb_type: u8 align(1),
    _0: u16 align(1) = 0,
};

pub var commandLine: [*]u8 = undefined;
pub var bootloaderName: [*]u8 = undefined;
pub var memoryLower: u32 = undefined;
pub var memoryUpper: u32 = undefined;
pub var entrySize: u32 = undefined;
pub var entryVersion: u32 = undefined;
pub var entries: []MultibootMemoryMapEntry = undefined;
pub var framebuffer: MultibootFramebufferEntry = undefined;

pub var modules: [1]MultibootModuleEntry = undefined;
pub var modulesCount: usize = 0;

pub fn init(multiboot_info_address: usize) void {
    var entry_address = root.KERNEL_BASE + multiboot_info_address + 8;

    while (true) {
        const entry: *const MultibootEntry = @ptrFromInt(entry_address);
        if (entry.type == .end) break;

        console.println("[multiboot] Type {}", .{entry.type});

        blk: switch (entry.type) {
            .cmdline => commandLine = @ptrFromInt(entry_address + TAG_SIZE),
            .bootloaderName => bootloaderName = @ptrFromInt(entry_address + TAG_SIZE),
            .basicMemInfo => {
                const basic_memory: [*]u32 = @ptrFromInt(entry_address + TAG_SIZE);
                memoryLower = basic_memory[0];
                memoryUpper = basic_memory[1];
            },
            .module => {
                if (modulesCount == modules.len) {
                    console.println("Unable to load more than {} modules", .{modules.len});
                    break :blk;
                }

                const mod_start: *u32 = @ptrFromInt(entry_address + TAG_SIZE);
                const mod_end: *u32 = @ptrFromInt(entry_address + TAG_SIZE + @sizeOf(u32));
                const string: [*:0]u8 = @ptrFromInt(entry_address + TAG_SIZE + 2 * @sizeOf(u32));

                console.println("Loading module \"{s}\"", .{string});

                const module = MultibootModuleEntry{
                    .data_addr = mod_start.*,
                    .data_len = mod_end.* - mod_start.*,
                    .str_addr = @intFromPtr(string),
                };

                modules[modulesCount] = module;
                modulesCount += 1;
            },
            .mmap => {
                const memory_map: [*]u32 = @ptrFromInt(entry_address + TAG_SIZE);
                entrySize = memory_map[0];
                entryVersion = memory_map[1];

                const entries_offset = TAG_SIZE + @sizeOf(u32) * 2;
                const entriesPtr: [*]MultibootMemoryMapEntry = @ptrFromInt(entry_address + entries_offset);
                const entriesCount = (entry.size - entries_offset) / entrySize;
                entries = entriesPtr[0..entriesCount];
            },
            .framebuffer => {
                const fb: *MultibootFramebufferEntry = @ptrFromInt(entry_address + TAG_SIZE);
                framebuffer = fb.*;
                console.println("{}", .{framebuffer});
            },
            else => {},
        }

        entry_address += (entry.size + 7) & ~@as(usize, 7);
    }
}
