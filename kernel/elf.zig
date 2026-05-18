const std = @import("std");

pub const Abi = packed struct(u16) {
    os: u8,
    version: u8,
};

pub const MAGIC: u32 = std.mem.bytesAsValue(u32, "\x7FELF").*;

pub const Identifier = packed struct(u128) {
    magic: u32,
    bit_size: enum(u8) { bit32 = 1, bit64 = 2 },
    endian: enum(u8) { little = 1, big = 2 },
    version: u8,
    abi: Abi,
    reserved0: u56,
};

pub const ObjectKind = enum(u16) {
    none = 0x00,
    relocatable = 0x01,
    executable = 0x02,
    dynamic = 0x03,
    core = 0x04,
    _,
    // 0xFE00-0xFEFF is OS-specific
    // 0xFF00-0xFFFF is processor-specific
};

pub const Architecture = enum(u16) {
    x86 = 0x03,
    _,
};

pub const Header = extern struct {
    id: Identifier,
    kind: ObjectKind,
    machine: Architecture,
    version: u32,
    entry_addr: usize,
    program_header_offset: usize,
    section_header_offset: usize,
    flags: u32,
    header_size: u16,
    program_header_size: u16,
    program_header_entries: u16,
    section_header_size: u16,
    section_header_entries: u16,
    section_name_index: u16,
};

pub const SegmentKind = enum(u32) {
    null = 0,
    load = 1,
    dynamic = 2,
    interp = 3,
    note = 4,
    program_header = 6,
    gnu_stack = 0x6474e551,
    _,
};

pub const ProgramFlags = packed struct(u32) {
    executable: bool,
    writeable: bool,
    readable: bool,
    unused0: u29,
};

pub const ProgramHeader = extern struct {
    kind: SegmentKind,
    offset: usize,
    vaddr: usize,
    paddr: usize,
    file_size: u32,
    mem_size: u32,
    flags: ProgramFlags,
    alignment: usize,
};

pub const SectionKind = enum(u32) {
    null = 0,
    progbits = 1,
    symbol = 2,
    string = 3,
    relocation_addend = 4,
    hash = 5,
    dynamic = 6,
    note = 7,
    nobits = 8,
    relocation = 9,
    reserved0 = 10,
    dynamic_symbol = 11,
    _,
};

pub const SectionFlags = packed struct(u32) {
    writeable: bool,
    allocated: bool,
    executable: bool,
    unused0: u29,
};

pub const SectionHeader = extern struct {
    section_name_offset: usize,
    kind: SectionKind,
    flags: SectionFlags,
    vaddr: usize,
    offset: usize,
    size: usize,
    link: u32,
    info: u32,
    alignment: usize,
    /// Entry size if section holds table
    entry_size: usize,
};
