const console = @import("../../console.zig");
const keyboard = @import("../../keyboard.zig");
const interrupts = @import("interrupts.zig");
const pic = @import("pic.zig");
const port = @import("port.zig");

const DATA_PORT = 0x60;
const STATUS_PORT = 0x64;
const COMMAND_PORT = 0x64;

pub fn init() void {
    interrupts.registerIrq(1, keyboardIrq);
}

fn keyboardIrq() void {
    if (port.inb(STATUS_PORT) & 1 == 0)
        return;

    const scancode = port.inb(DATA_PORT);
    // console.println("[ps2] scancode: {X}", .{data});

    keyboard.pushScancode(scancode);
}
