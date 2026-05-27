pub const StdFd = enum(u8) {
    in = 0,
    out = 1,

    pub const count = @typeInfo(@This()).@"enum".fields.len;
};
pub const STDIN = @intFromEnum(StdFd.in);
pub const STDOUT = @intFromEnum(StdFd.out);

pub const NodeKind = enum(u8) {
    file,
    dir,
    device,
};

pub const Stat = extern struct {
    kind: NodeKind,
    size: usize,
    mountpoint: [32]u8 = undefined,
    mountpoint_len: usize,
    filesystem: [32]u8 = undefined,
    filesystem_len: usize,
};

pub const DirEntry = extern struct {
    name: [32]u8 = undefined,
    name_len: usize,
};
