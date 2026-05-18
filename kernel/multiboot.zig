// https://www.gnu.org/software/grub/manual/multiboot2/multiboot.html
const root = @import("root.zig");
const console = root.console;

const MultibootHeaderTag = extern struct {
    type: u16 align(1),
    flags: u16 align(1),
    size: u32 align(1),
};

const MultibootHeader = extern struct {
    magic: u32 align(8),
    architecture: u32 align(1),
    header_length: u32 align(1),
    checksum: u32 align(1),
    end_tag: MultibootHeaderTag align(8),
};

const MAGIC = 0xE85250D6;
const ARCHITECTURE = 0; // i386 (protected mode)
const HEADER_LENGTH = @sizeOf(MultibootHeader);

// Cannot be read after boot because this is located in the lower-half.
pub const multiboot align(8) linksection(".multiboot") = MultibootHeader{
    .magic = MAGIC,
    .architecture = ARCHITECTURE,
    .header_length = HEADER_LENGTH,
    .checksum = 0x100000000 - (MAGIC + ARCHITECTURE + HEADER_LENGTH),
    .end_tag = .{ .type = 0, .flags = 0, .size = @sizeOf(MultibootHeaderTag) },
};

const MultibootTagType = enum(u32) { end = 0, cmdline = 1, bootloaderName = 2, module = 3, basicMemInfo = 4, mmap = 6, _ };

const MultibootTag = extern struct {
    type: MultibootTagType align(8),
    size: u32 align(1),
};

const TAG_SIZE = @sizeOf(MultibootTag);

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

pub var commandLine: [*]u8 = undefined;
pub var bootloaderName: [*]u8 = undefined;
pub var memoryLower: u32 = undefined;
pub var memoryUpper: u32 = undefined;
pub var entrySize: u32 = undefined;
pub var entryVersion: u32 = undefined;
pub var entries: []MultibootMemoryMapEntry = undefined;
// pub var acpiVersion2: bool = undefined;
// pub var acpiOldRsdp: acpi.rsdp = undefined;
// pub var acpiNewRsdp: acpi.rsdp_20 = undefined;

pub var modules: [1]MultibootModuleEntry = undefined;
pub var modulesCount: usize = 0;

pub fn init(multiboot_info_address: usize) void {
    var entry_address = root.KERNEL_BASE + multiboot_info_address + 8;

    while (true) {
        const entry: *const MultibootTag = @ptrFromInt(entry_address);
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
            // 14 => {
            //     acpiVersion2 = false;

            //     const rsdp: *acpi.rsdp = @ptrFromInt(entry_address + TAG_SIZE);
            //     acpiOldRsdp = rsdp.*;
            // },
            // 15 => {
            //     acpiVersion2 = true;

            //     const rsdp: *acpi.rsdp_20 = @ptrFromInt(entry_address + TAG_SIZE);
            //     acpiNewRsdp = rsdp.*;
            // },
            else => {},
        }

        entry_address += (entry.size + 7) & ~@as(usize, 7);
    }
}
