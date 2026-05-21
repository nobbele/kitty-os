const console = @import("root").console;
const ps2 = @import("root").arch.ps2;

pub const UNSHIFTED_MAP = [_]u8{
    0,    27,  '1', '2', '3', '4', '5', '6', '7',  '8', '9', '0',  '-',  '=', 8,   '\t',
    'q',  'w', 'e', 'r', 't', 'y', 'u', 'i', 'o',  'p', '[', ']',  '\n', 0,   'a', 's',
    'd',  'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`', 0,   '\\', 'z',  'x', 'c', 'v',
    'b',  'n', 'm', ',', '.', '/', 0,   '*', 0,    ' ', 0,   0,    0,    0,   0,   0,
    0,    0,   0,   0,   0,   0,   0,   0,   0,    0,   0,   0,    0,    0,   0,   0,
    '\\', 0,   0,   0,   0,   0,   0,   0,   0,    0,   0,   0,    0,    0,   0,   0,
    0,    0,   0,   0,   0,   0,   0,   0,   0,    0,   0,   0,    0,    0,   0,   0,
    0,    0,   0,   0,   0,   0,   0,   0,   0,    0,   0,   0,    0,    0,   0,   0,
};

pub const SHIFTED_MAP = [_]u8{
    0,   27,  '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_',  '+', 8,   '\t',
    'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', '\n', 0,   'A', 'S',
    'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~', 0,   '|', 'Z',  'X', 'C', 'V',
    'B', 'N', 'M', '<', '>', '?', 0,   '*', 0,   ' ', 0,   0,   0,    0,   0,   0,
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,    0,   0,   0,
    '|', 0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,    0,   0,   0,
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,    0,   0,   0,
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,    0,   0,   0,
};

var shifted = false;

var kbd_buffer: [16]u8 = undefined;
var kbd_write: usize = 0;
var kbd_read: usize = 0;

pub fn pushScancode(scancode: u8) void {
    kbd_buffer[kbd_write] = scancode;
    kbd_write = (kbd_write + 1) % kbd_buffer.len;
}

pub fn tryReadScancode() ?u8 {
    if (kbd_write == kbd_read) return null;

    const data = kbd_buffer[kbd_read];
    kbd_read = (kbd_read + 1) % kbd_buffer.len;
    return data;
}

pub fn readKey() u8 {
    while (true) {
        if (tryReadKey()) |k| return k;
        // TODO don't spin?
    }
}

pub fn tryReadKey() ?u8 {
    var data = tryReadScancode() orelse return null;

    const pressed = data & 0x80 == 0;
    if (!pressed) data -= 0x80;

    // LShift and RShift
    if (data == 0x2A or data == 0x36) {
        shifted = pressed;
        return tryReadKey();
    }

    // Caps Lock
    if (data == 0x3A) {
        if (pressed) shifted = !shifted;
        return tryReadKey();
    }

    if (data >= 128) {
        console.println("[keyboard] Out of range key", .{});
    }

    // Ignore releasing keys
    if (!pressed) return tryReadKey();

    const map = if (shifted) SHIFTED_MAP else UNSHIFTED_MAP;

    const char = map[data];
    if (char == 0) {
        console.serialPrintln("[keyboard] Invalid key", .{});
        return null;
    }

    return char;
}
