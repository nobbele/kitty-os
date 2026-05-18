const std = @import("std");

const port = @import("port.zig");

pub const VEC_START = 0x20;
pub const VEC_END = VEC_START + 16;

// Master PIC
const PIC1_COMMAND = 0x20;
const PIC1_DATA = 0x21;

// Slave PIC
const PIC2_COMMAND = 0xA0;
const PIC2_DATA = 0xA1;

const PIC_EOI = 0x20;

const ICW1_ICW4 = 0x01;
const ICW1_SINGLE = 0x02;
const ICW1_INTERVAL4 = 0x04;
const ICW1_LEVEL = 0x08;
const ICW1_INIT = 0x10;

const ICW4_8086 = 0x01;
const ICW4_AUTO = 0x02;
const ICW4_BUF_SLAVE = 0x08;
const ICW4_BUF_MASTER = 0x0C;
const ICW4_SFNM = 0x10;

const CASCADE_IRQ = 2;

fn remap(offset1: u8, offset2: u8) void {
    // Start the initialization sequence
    port.outb(PIC1_COMMAND, ICW1_INIT | ICW1_ICW4);
    port.ioWait();
    port.outb(PIC2_COMMAND, ICW1_INIT | ICW1_ICW4);
    port.ioWait();

    // ICW2: Master PIC vector offset
    port.outb(PIC1_DATA, offset1);
    port.ioWait();

    // ICW2: Slave PIC vector offset
    port.outb(PIC2_DATA, offset2);
    port.ioWait();

    // ICW3: Tell Master PIC that there is a slave PIC at IRQ 2 (0000 0100)
    port.outb(PIC1_DATA, 1 << CASCADE_IRQ);
    port.ioWait();

    // ICW3: Tell Slave PIC its cascade identity (0000 0010)
    port.outb(PIC2_DATA, 2);
    port.ioWait();

    // ICW4: have the PICs use 8086 mode (and not 8080 mode)
    port.outb(PIC1_DATA, ICW4_8086);
    port.ioWait();
    port.outb(PIC2_DATA, ICW4_8086);
    port.ioWait();

    port.outb(PIC1_DATA, 0xFF);
    port.outb(PIC2_DATA, 0xFF);
}

pub fn sendEoi(irq: u8) void {
    if (irq >= 8) port.outb(PIC2_COMMAND, PIC_EOI);
    port.outb(PIC1_COMMAND, PIC_EOI);
}

pub fn init() void {
    remap(VEC_START, VEC_START + 8);
}

pub fn setIrqMask(irq: u8) void {
    var portq: u16 = 0;
    var intr = irq;

    if (intr < 8) {
        portq = PIC1_DATA;
    } else {
        portq = PIC2_DATA;
        intr -= 8;
    }

    var value: std.bit_set.IntegerBitSet(8) = .{ .mask = port.inb(portq) };
    value.set(intr);
    port.outb(portq, value.mask);
}

pub fn clearIrqMask(irq: u8) void {
    var portq: u16 = 0;
    var intr = irq;

    if (intr < 8) {
        portq = PIC1_DATA;
    } else {
        portq = PIC2_DATA;
        intr -= 8;
    }

    var value: std.bit_set.IntegerBitSet(8) = .{ .mask = port.inb(portq) };
    value.unset(intr);
    port.outb(portq, value.mask);
}
