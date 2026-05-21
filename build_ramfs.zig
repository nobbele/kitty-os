const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    var opt_out_path: ?[]const u8 = null;
    var inputs: std.ArrayList(struct {
        dest: []const u8,
        src: []const u8,
    }) = .empty;

    {
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (std.mem.eql(u8, "-o", arg)) {
                i += 1;
                if (i > args.len) fatal("expected arg after '{s}'", .{arg});
                if (opt_out_path != null) fatal("duplicated {s} argument", .{arg});
                opt_out_path = args[i];
            } else {
                var it = std.mem.splitScalar(u8, arg, ':');
                const dest = it.next() orelse fatal("Missing dest path", .{});
                const src = it.next() orelse fatal("Missing src path", .{});
                try inputs.append(arena, .{
                    .dest = dest,
                    .src = src,
                });
            }
        }
    }

    const out_path = opt_out_path orelse fatal("missing -o (Output)", .{});

    var output_file = Io.Dir.cwd().createFile(io, out_path, .{}) catch |err| {
        fatal("unable to open '{s}': {s}", .{ out_path, @errorName(err) });
    };
    defer output_file.close(io);

    var out_buffer: [1000]u8 = undefined;
    var out_writer = output_file.writer(io, &out_buffer);
    var tar_writer: std.tar.Writer = .{ .underlying_writer = &out_writer.interface };

    for (inputs.items) |input| {
        var src_file = Io.Dir.cwd().openFile(io, input.src, .{}) catch |err| {
            fatal("unable to open '{s}': {s}", .{ input.src, @errorName(err) });
        };
        defer src_file.close(io);

        var src_buffer: [1000]u8 = undefined;
        var src_file_reader = src_file.reader(io, &src_buffer);
        try tar_writer.writeFile(input.dest, &src_file_reader, 0);
    }
    try out_writer.end();

    return std.process.cleanExit(io);
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
