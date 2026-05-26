const std = @import("std");
const root = @import("root");
const multiboot = root.multiboot;

const termfont align(4) = @embedFile("Lat2-Terminus16.psfu");

var fb: [*]u32 = undefined;
var font: Font = undefined;
var global: Terminal = undefined;

pub fn init() !void {
    fb = @ptrFromInt(@as(usize, @intCast(multiboot.framebuffer.addr)));
    font = try .init(termfont);
    global = .{
        .columns = multiboot.framebuffer.width / font.header.width,
        .rows = multiboot.framebuffer.height / font.header.height,
    };
}

const PSF2_MAGIC = 0x864ab572;

const PSF2Header = extern struct {
    magic: u32,
    version: u32,
    header_size: u32,
    flags: u32,
    glyph_count: u32,
    bytes_per_glyph: u32,
    height: u32,
    width: u32,
};

pub const Font = struct {
    header: *const PSF2Header,
    glyphs: []const u8,

    pub fn init(data: []const u8) !Font {
        if (data.len < @sizeOf(PSF2Header)) return error.TooSmall;
        const header: *const PSF2Header = @ptrCast(@alignCast(data.ptr));
        if (header.magic != PSF2_MAGIC) return error.InvalidMagic;
        if (data.len < header.header_size + header.glyph_count * header.bytes_per_glyph)
            return error.TruncatedData;
        return .{
            .header = header,
            .glyphs = data[header.header_size..],
        };
    }

    pub fn glyph(self: Font, char: u8) []const u8 {
        const start = @as(usize, char) * self.header.bytes_per_glyph;
        return self.glyphs[start .. start + self.header.bytes_per_glyph];
    }
};

fn posToIdx(
    x: usize,
    dx: usize,
    y: usize,
    dy: usize,
) usize {
    return (y * font.header.height + dy) * (multiboot.framebuffer.pitch / 4) + (x * font.header.width + dx);
}

pub fn drawChar(x: usize, y: usize, char: u8, fg: u32, bg: u32) void {
    const glyph = font.glyphs[char * font.header.bytes_per_glyph ..];

    for (0..font.header.height) |row| {
        const stride = std.math.divCeil(usize, font.header.width, 8) catch unreachable;
        const bits = glyph[row * stride];
        for (0..font.header.width) |col| {
            const set = ((bits >> @intCast(7 - col)) & 1) > 0;
            fb[posToIdx(x, col, y, row)] = if (set) fg else bg;
        }
    }
}

pub fn drawImage(x: usize, y: usize, data: [*]const u32, width: usize, height: usize) void {
    for (0..height) |dy| {
        for (0..width) |dx| {
            const pixel = data[dy * width + dx];
            const r = (pixel >> 16) & 0xFF;
            const g = (pixel >> 8) & 0xFF;
            const b = (pixel >> 0) & 0xFF;
            const a = (pixel >> 24) & 0xFF;
            fb[posToIdx(x, dx, y, dy)] = (a << 24) | (r << 0) | (g << 8) | (b << 16);
        }
    }
}

pub fn clearChar(x: usize, y: usize) void {
    for (0..font.header.height) |row| {
        for (0..font.header.width) |col| {
            fb[posToIdx(x, col, y, row)] = 0;
        }
    }
}

const Terminal = struct {
    column: usize = 0,
    row: usize = 0,
    columns: usize,
    rows: usize,
    fg: u32 = 0xFFFFFFFF,
    bg: u32 = 0,

    pub fn deleteChar(self: *Terminal) void {
        if (self.column == 0) {
            if (self.row != 0) {
                self.row -= 1;
                self.column = self.columns - 1;
            }
        } else {
            self.column -= 1;
        }

        clearChar(self.column, self.row);
    }

    pub fn printChar(self: *Terminal, char: u8) void {
        switch (char) {
            '\n' => {
                self.column = 0;
                self.nextRow();
            },
            '\r' => {
                self.column = 0;
            },
            // BS
            8 => {
                self.deleteChar();
            },
            else => {
                drawChar(self.column, self.row, char, self.fg, self.bg);
                self.column += 1;
                if (self.column >= self.columns) {
                    self.column = 0;
                    self.nextRow();
                }
            },
        }
    }

    fn nextRow(self: *Terminal) void {
        self.row += 1;
        while (self.row >= self.rows) {
            self.scroll();
            self.row = self.rows - 1;
        }
    }

    fn scroll(self: *Terminal) void {
        const row_quads = font.header.height * multiboot.framebuffer.pitch / 4;
        @memmove(fb[0 .. (self.rows - 1) * row_quads], fb[row_quads .. self.rows * row_quads]);
        @memset(fb[(self.rows - 1) * row_quads .. self.rows * row_quads], 0);
    }
};

pub fn printString(str: []const u8) void {
    for (str) |char| {
        global.printChar(char);
    }
}

fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) !usize {
    // the length of data must not be zero
    std.debug.assert(data.len != 0);

    var consumed: usize = 0;
    const pattern = data[data.len - 1];
    const splat_len = pattern.len * splat;

    // If buffer is not empty write it first
    if (w.end != 0) {
        printString(w.buffered());
        w.end = 0;
    }

    // Now write all data except last element
    for (data[0 .. data.len - 1]) |bytes| {
        printString(bytes);
        consumed += bytes.len;
    }

    // If out patter (i.e. last element of data) is non zero len then write splat times
    switch (pattern.len) {
        0 => {},
        else => {
            for (0..splat) |_| {
                printString(pattern);
            }
        },
    }
    // Now we have to return how many bytes we consumed from data
    consumed += splat_len;
    return consumed;
}

const drain_vtable: std.Io.Writer.VTable = .{ .drain = drain };

pub fn writer(buffer: []u8) std.Io.Writer {
    return .{
        .buffer = buffer,
        .end = 0,
        .vtable = &drain_vtable,
    };
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var w = writer(&.{});
    w.print(fmt, args) catch return;
}

pub fn println(comptime fmt: []const u8, args: anytype) void {
    var w = writer(&.{});
    w.print(fmt, args) catch return;
    w.printAsciiChar('\n', .{}) catch return;
}

pub fn moveTo(x: usize, y: usize) void {
    global.column = x;
    global.row = y;
    if (global.column >= global.columns) {
        global.column = 0;
        global.nextRow();
    }
}

pub fn putImage(data: [*]const u32, width: usize, height: usize) void {
    const columns = std.math.divCeil(usize, width, font.header.width) catch unreachable;
    const rows = std.math.divCeil(usize, height, font.header.height) catch unreachable;

    if (columns > global.columns)
        @panic("Image is too wide");

    if (rows > global.rows)
        @panic("Image is too tall");

    const x = global.column;
    const y = global.row;

    global.column = 0;
    global.row += rows;
    while (global.row >= global.rows) {
        global.scroll();
        global.row = global.rows - 1;
    }

    drawImage(x, y, data, width, height);
}
