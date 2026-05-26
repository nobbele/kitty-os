pub const StdFd = enum(u8) {
    in = 0,
    out = 1,

    pub const count = @typeInfo(@This()).@"enum".fields.len;
};
pub const STDIN = @intFromEnum(StdFd.in);
pub const STDOUT = @intFromEnum(StdFd.out);

pub const NodeKind = enum(u8) { file, directory };

pub const Stat = extern struct {
    kind: NodeKind,
    size: usize,
};

pub const DirEntry = extern struct {
    name: [*]const u8,
    name_len: usize,
};
