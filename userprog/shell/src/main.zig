const std = @import("std");

const kitty = @import("kitty");

export fn _start() callconv(.naked) void {
    asm volatile ("call main");
    asm volatile (
        \\ int $0x80
        :
        : [syscall] "{eax}" (5),
          [code] "{ebx}" (0),
    );
}

export fn main() callconv(.{ .x86_sysv = .{} }) void {
    // asm volatile (
    //     \\ mov %[deadbeef], %%eax
    //     :
    //     : [deadbeef] "i" (kitty.a),
    //     : .{ .eax = true });

    // while (true) {
    //     kitty.print("Hello World\n", .{});

    //     kitty.sleep(1000);
    // }

    kitty.println("Hello World", .{});

    // while (true) {
    //     var buffer: [64]u8 = undefined;

    //     kitty.print(">", .{});
    //     const read = kitty.readLine(&buffer) catch 0;
    //     const string = buffer[0..read];
    //     _ = string; // autofix
    // }

    // var x: usize = 0;
    // while (true) {
    //     x += 1;
    //     kitty.write(1, std.fmt.bufPrint(&buffer, "Hello World {}\n", .{x}) catch unreachable);
    //     kitty.sleep(1000);

    //     if (x == 7000) {
    //         kitty.exec();
    //     }
    // }
}
