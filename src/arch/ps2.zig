const console = @import("../console.zig");
const interrupts = @import("interrupts.zig");
const pic = @import("pic.zig");
const port = @import("port.zig");

const DATA_PORT = 0x60;
const STATUS_PORT = 0x64;
const COMMAND_PORT = 0x64;

var kbd_buffer: [16]u8 = undefined;
var kbd_write: usize = 0;
var kbd_read: usize = 0;

pub fn init() void {
    interrupts.register_hardware_interrupt(1, keyboardInterrupt);
}

fn keyboardInterrupt() void {
    if (port.inb(STATUS_PORT) & 1 == 0)
        return;

    const data = port.inb(DATA_PORT);
    // console.println("[ps2] scancode: {X}", .{data});

    kbd_buffer[kbd_write] = data;
    kbd_write = (kbd_write + 1) % kbd_buffer.len;
}

pub fn readKeyboard() u8 {
    // Wait until there's data to retreieve
    while (kbd_write == kbd_read) {
        port.ioWait();
    }

    const data = kbd_buffer[kbd_read];
    kbd_read = (kbd_read + 1) % kbd_buffer.len;
    return data;
}
