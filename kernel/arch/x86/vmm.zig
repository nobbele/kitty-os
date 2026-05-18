const std = @import("std");

const console = @import("../../console.zig");
const root = @import("../../root.zig");
const mmu = @import("mmu.zig");
const pmm = @import("pmm.zig");

pub var kernel_address_space: AddressSpace = undefined;
pub var kernel_entries: [*]mmu.PageDirEntry = undefined;

pub fn init() !void {
    const kernel_dir_phys = pmm.alloc(mmu.PAGE_DIRECTORY_COUNT * @sizeOf(u32)) orelse return error.OutOfMemory;
    kernel_entries = @ptrFromInt(root.KERNEL_BASE + kernel_dir_phys);
    @memset(kernel_entries[0..mmu.PAGE_DIRECTORY_COUNT], @bitCast(@as(u32, 0)));

    for (0..pmm.total_pages) |page_no| {
        const virt = root.KERNEL_BASE + (page_no * root.PAGE_SIZE);
        const phys = page_no * root.PAGE_SIZE;
        mapInto(kernel_entries, virt, phys, .{}) catch |err| switch (err) {
            error.AlreadyMapped => continue,
            else => return err,
        };
    }

    console.println("[vmm] Mapping VGA buffer", .{});
    try mapInto(kernel_entries, 0xC03FF000, 0x000B8000, .{ .overwrite = true });

    console.println("[vmm] Creating kernel address space", .{});
    kernel_address_space = try AddressSpace.init();

    console.println("[vmm] Loading kernel address space", .{});
    kernel_address_space.load();
    console.println("[vmm] Done", .{});
}

fn mapInto(pd: [*]mmu.PageDirEntry, virt: usize, phys: usize, opts: MappingOptions) !void {
    if (!std.mem.isAligned(virt, root.PAGE_SIZE) or !std.mem.isAligned(phys, root.PAGE_SIZE))
        return error.UnalignedAddress;

    const pdi = virt >> 22;
    const pti = (virt >> 12) & 0x3FF;

    const pde = &pd[pdi];

    if (!pde.flags.present) {
        const pt_phys = pmm.alloc(mmu.PAGE_TABLE_COUNT * @sizeOf(u32)) orelse return error.OutOfMemory;

        const pt: [*]mmu.PageTableEntry = @ptrFromInt(root.KERNEL_BASE + pt_phys);
        @memset(pt[0..mmu.PAGE_TABLE_COUNT], @bitCast(@as(u32, 0)));

        pde.address_high = @truncate(pt_phys >> 12);
        pde.flags = .{
            .present = true,
            .writable = opts.writable,
            .access = opts.access,
        };
    } else {
        // Upgrade table entry if new mapping needs broader access
        if (opts.access == .user) pde.flags.access = .user;
        if (opts.writable) pde.flags.writable = true;
    }

    const pt_phys: usize = @as(usize, pde.address_high) << 12;
    const pt: [*]mmu.PageTableEntry = @ptrFromInt(root.KERNEL_BASE + pt_phys);
    const pte = &pt[pti];

    if (pte.flags.present and !opts.overwrite) {
        return error.AlreadyMapped;
    }

    pte.flags = .{ .present = true, .writable = opts.writable, .access = opts.access };
    pte.address_high = @truncate(phys >> 12);
}

fn unmapFrom(pd: [*]mmu.PageDirEntry, virt: usize) !void {
    if (!std.mem.isAligned(virt, root.PAGE_SIZE))
        return error.UnalignedAddress;

    const pdi = virt >> 22;
    const pti = (virt >> 12) & 0x3FF;
    const pde = &pd[pdi];

    if (!pde.flags.present)
        return error.NotMapped;

    const pt_phys: usize = @as(usize, pde.address_high) << 12;
    const pt: [*]mmu.PageTableEntry = @ptrFromInt(root.KERNEL_BASE + pt_phys);
    const pte = &pt[pti];

    if (!pte.flags.present)
        return error.NotMapped;

    pte.* = @bitCast(@as(u32, 0));
}

pub const AddressSpace = struct {
    page_dir: usize,

    pub fn init() !AddressSpace {
        const dir_phys = pmm.alloc(mmu.PAGE_DIRECTORY_COUNT * @sizeOf(u32)) orelse return error.OutOfMemory;
        const self: AddressSpace = .{ .page_dir = dir_phys };

        const entries = self.dirEntries();
        @memset(entries, @bitCast(@as(u32, 0)));

        // share kernel mappings (upper 256 entries)
        @memcpy(entries[768..1024], kernel_entries[768..1024]);

        return self;
    }

    pub fn dirEntries(self: *const AddressSpace) *[mmu.PAGE_DIRECTORY_COUNT]mmu.PageDirEntry {
        const entries_ptr: [*]mmu.PageDirEntry = @ptrFromInt(root.KERNEL_BASE + self.page_dir);
        return entries_ptr[0..mmu.PAGE_DIRECTORY_COUNT];
    }

    pub fn mapRange(self: *const AddressSpace, virt: usize, phys: usize, length: usize, opts: MappingOptions) !void {
        const aligned_length = std.mem.alignForward(usize, length, root.PAGE_SIZE);
        var offset: usize = 0;
        while (offset < aligned_length) : (offset += root.PAGE_SIZE) {
            try self.map(virt + offset, phys + offset, opts);
        }
    }

    pub fn unmapRange(self: *const AddressSpace, virt: usize, length: usize) !void {
        const aligned_length = std.mem.alignForward(usize, length, root.PAGE_SIZE);
        var offset: usize = 0;
        while (offset < aligned_length) : (offset += root.PAGE_SIZE) {
            try self.unmap(virt + offset);
        }
    }

    pub fn map(self: *const AddressSpace, virt: usize, phys: usize, opts: MappingOptions) !void {
        const pd = self.dirEntries();
        try mapInto(pd, virt, phys, opts);

        // sync kernel mappings back to kernel_entries
        if (virt >= root.KERNEL_BASE) {
            const pdi = virt >> 22;
            kernel_entries[pdi] = self.dirEntries()[pdi];
        }

        asm volatile ("invlpg (%[addr])"
            :
            : [addr] "r" (virt),
        );
    }

    pub fn unmap(self: *const AddressSpace, virt: usize) !void {
        const pd = self.dirEntries();
        try unmapFrom(pd, virt);

        // sync kernel mappings back to kernel_entries
        if (virt >= root.KERNEL_BASE) {
            const pdi = virt >> 22;
            kernel_entries[pdi] = self.dirEntries()[pdi];
        }

        asm volatile ("invlpg (%[addr])"
            :
            : [addr] "r" (virt),
        );
    }

    pub fn load(self: *const AddressSpace) void {
        asm volatile ("mov %[pd], %%cr3"
            :
            : [pd] "r" (self.page_dir),
        );
    }
};

pub const MappingOptions = struct {
    writable: bool = true,
    access: mmu.Access = .kernel,
    overwrite: bool = false,
};
