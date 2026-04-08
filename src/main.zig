const std = @import("std");

pub fn main() !void {
    const data_dir_path = "/home/djamla/code/git/kvz/data/";

    var data_dir = try std.fs.openDirAbsolute(data_dir_path, .{});
    defer data_dir.close();

    const f: std.fs.File = try data_dir.openFile("data.bin", .{ .mode = .read_write });
    defer f.close();
    const res = try f.write("init");
    try f.seekTo(res);
    const bytes_written = try f.write(" Database");

    std.debug.print("{d}\n", .{bytes_written});
}
