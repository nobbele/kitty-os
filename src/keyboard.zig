const ps2 = @import("arch/x86/ps2.zig");
const console = @import("console.zig");

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

pub fn readKey() u8 {
    var data = ps2.readKeyboard();

    const pressed = data & 0x80 == 0;
    if (!pressed) data -= 0x80;

    // LShift and RShift
    if (data == 0x2A or data == 0x36) {
        shifted = pressed;
        return readKey();
    }

    // Caps Lock
    if (data == 0x3A) {
        if (pressed) shifted = !shifted;
        return readKey();
    }

    // Ignore releasing keys
    if (!pressed) return readKey();

    const map = if (shifted) SHIFTED_MAP else UNSHIFTED_MAP;

    if (data >= 128) @panic("[keyboard] Out of range key");
    const char = map[data];
    if (char == 0) @panic("[keyboard] Invalid key");

    return char;
}
