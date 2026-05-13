const std = @import("std");

const console = @import("console.zig");
const keyboard = @import("keyboard.zig");

pub fn run() noreturn {
    while (true) {
        console.printChar('>');

        var cmd_buffer = [_]u8{0} ** 192;
        var cmd_write: usize = 0;
        while (true) {
            const char = keyboard.readKey();

            // Handle backspace
            if (char == 8) {
                if (cmd_write > 0)
                    console.deleteChar();

                cmd_write -|= 1;
                continue;
            }

            if (char == '\n')
                break;

            cmd_buffer[cmd_write] = char;
            cmd_write += 1;

            console.printChar(char);
        }

        console.printChar('\n');

        const cmdline = cmd_buffer[0..cmd_write];

        var argv: [16][]const u8 = undefined;
        var argc: usize = 0;

        var it = std.mem.splitScalar(u8, cmdline, ' ');
        while (it.next()) |arg| {
            argv[argc] = arg;
            argc += 1;
        }

        exec(argv[0..argc]);
    }
}

fn exec(args: [][]const u8) void {
    if (args.len == 0) return;
    const cmd = args[0];
    if (std.mem.eql(u8, cmd, "echo")) {
        echo(args);
    } else {
        console.println("Unknown command '{s}'", .{cmd});
    }
}

fn echo(args: [][]const u8) void {
    for (args[1..], 0..) |arg, i| {
        console.printString(arg);
        if (i != args.len - 1) console.printChar(' ');
    }
    console.printChar('\n');
}
