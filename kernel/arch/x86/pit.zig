const port = @import("port.zig");

const CHANNEL0_DATA: u16 = 0x40;
const COMMAND: u16 = 0x43;
const BASE_FREQ: u32 = 1193182;

const ModeCmd = packed struct(u8) {
    bcd: bool,
    operating: enum(u3) { square_wave = 3 },
    access: enum(u2) { latch, low, high, pair },
    channel: u2,
};

pub fn init(channel: u2, freq: u32) void {
    const divisor: u16 = @truncate(BASE_FREQ / freq);

    port.outb(COMMAND, @bitCast(ModeCmd{
        .bcd = false,
        .operating = .square_wave,
        .access = .pair,
        .channel = channel,
    }));
    port.outb(CHANNEL0_DATA, @truncate(divisor & 0xFF));
    port.outb(CHANNEL0_DATA, @truncate(divisor >> 8));
}
