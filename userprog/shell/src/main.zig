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
    kitty.println("Welcome to the KittyOS shell!", .{});

    var buffer: [64]u8 = undefined;
    while (true) {
        kitty.print(">", .{});
        const read = kitty.readLine(&buffer) catch 0;
        const cmdline = buffer[0..read];

        var it = std.mem.splitScalar(u8, cmdline, ' ');
        const path = it.next() orelse continue;
        // const args = it.rest();
        if (std.mem.eql(u8, path, "stat")) {
            var opt_filename = it.next();
            if (opt_filename) |filename| {
                if (filename.len == 0)
                    opt_filename = null;
            }

            const filename = opt_filename orelse {
                kitty.println("Missing required argument 'filename'", .{});
                continue;
            };

            var stat: kitty.fs.Stat = undefined;
            kitty.syscall.stat(filename, &stat);

            kitty.println("File: {s} ({s})", .{ filename, @tagName(stat.kind) });
            kitty.println("Size: {Bi:.1} ({} bytes)", .{ stat.size, stat.size });
            kitty.println("Mountpoint: {s} ({s})", .{ stat.mountpoint[0..stat.mountpoint_len], stat.filesystem[0..stat.filesystem_len] });
        } else if (std.mem.eql(u8, path, "read")) {
            var opt_filename = it.next();
            if (opt_filename) |filename| {
                if (filename.len == 0)
                    opt_filename = null;
            }

            const filename = opt_filename orelse {
                kitty.println("Missing required argument 'filename'", .{});
                continue;
            };

            var stat: kitty.fs.Stat = undefined;
            kitty.syscall.stat(filename, &stat);

            // TODO dynamically allocate buffer
            var read_buffer: [256]u8 = undefined;

            const fd = kitty.syscall.open(filename);
            const bytes_read = kitty.syscall.read(fd, &read_buffer);
            if (bytes_read != stat.size) {
                kitty.println("Failed to read", .{});
                continue;
            }

            const data = read_buffer[0..bytes_read];

            if (stat.kind == .dir) {
                const entries = std.mem.bytesAsSlice(kitty.fs.DirEntry, data);
                for (entries) |entry| {
                    const name = entry.name[0..entry.name_len];

                    var full_path_buf: [256]u8 = undefined;
                    const full_path = std.fmt.bufPrint(&full_path_buf, "{s}/{s}", .{ filename, name }) catch {
                        kitty.println("Path too long", .{});
                        continue;
                    };

                    var entry_stat: kitty.fs.Stat = undefined;
                    kitty.syscall.stat(full_path, &entry_stat);

                    kitty.println("{s} ({s})", .{ name, @tagName(entry_stat.kind) });
                }
            } else {
                kitty.println("{X}", .{data});
            }
        } else {
            kitty.syscall.exec(path);
        }

        // TODO wait for processes
        for (0..3) |_| kitty.syscall.yield();
    }
}
