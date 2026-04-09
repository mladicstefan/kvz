const std = @import("std");
const debug = std.debug.print;
const net = std.net;
const posix = std.posix;
const log = std.log;
const expect = std.testing.expect;

pub fn main() !void {
    const PORT = 25556;
    const address = net.Address.initIp4(.{ 127, 0, 0, 1 }, PORT);
    const server = try posix.socket(posix.AF.INET, posix.SOCK.STREAM, 0);
    defer posix.close(server);

    try posix.setsockopt(server, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    try posix.bind(server, &address.any, address.getOsSockLen());
    try posix.listen(server, 128);
    log("Listening on port:{d}...\n", .{PORT});

    // var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    // uncomment in prod
    // defer arena.deinit();

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    _ = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) expect(false) catch @panic("Memory Leak");
    }
}
