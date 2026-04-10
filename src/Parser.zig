const meta = @import("std").meta;
const expect = @import("std").testing.expect;
const std = @import("std");
const debug = std.debug.print;

const ParserError = error{
    SyntaxError,
};

const MAX_LEN = 32;
const MAX_CMD_LEN = 5;

pub const Parser = @This();
query: []const u8,
tokens: [MAX_CMD_LEN][]const u8,
token_count: u8,

pub fn init() @This() {
    return .{ .query = undefined, .tokens = undefined, .token_count = 0 };
}

fn simdGetBitMask(query: []const u8, delimiter: u8) u32 {
    const len = query.len;
    var buf: [MAX_LEN]u8 = [_]u8{0} ** MAX_LEN;
    @memcpy(buf[0..len], query[0..len]);

    const query_vec: @Vector(MAX_LEN, u8) = buf;
    const delim_vec: @Vector(MAX_LEN, u8) = @splat(delimiter);

    const matches: @Vector(MAX_LEN, bool) = query_vec == delim_vec;
    return @bitCast(matches);
}

fn simdTokenize(self: *@This(), delimiter: u8) void {
    var prev: usize = 0;
    const len_mask: u32 = (@as(u32, 1) << @intCast(self.query.len));
    //const len_mask: u32 = (1 << x.len);
    // const len_mask = simdGetBitMask(x, '\r');
    var mask = simdGetBitMask(self.query, delimiter);
    mask ^= len_mask;
    const count = @popCount(mask);
    for (0..count) |i| {
        const pos = @ctz(mask);
        self.tokens[i] = self.query[prev..pos];
        self.token_count += 1;
        mask &= mask - 1;
        prev = pos + 1;
    }
}

pub fn parse(self: *@This(), query: []const u8) void {
    self.query = query;
    self.simdTokenize(' ');
}

test "parse" {
    // const tokens: [MAX_CMD_LEN][]const u8 = undefined;
    var p: Parser = init();
    const query: []const u8 = "A bat drew a cat";
    p.parse(query);
    debug("{any}\n", .{p});
    try std.testing.expectEqualStrings("A", p.tokens[0]);
    try std.testing.expectEqualStrings("bat", p.tokens[1]);
    try std.testing.expectEqualStrings("drew", p.tokens[2]);
    try std.testing.expectEqualStrings("a", p.tokens[3]);
    try std.testing.expectEqualStrings("cat", p.tokens[4]);
}

test "simdTokenize" {
    const query: []const u8 = "A bat drew a cat";

    // const tokens: [MAX_CMD_LEN][]const u8 = undefined;
    var p: Parser = init();
    p.query = query;
    p.simdTokenize(std.ascii.whitespace[0]);

    try std.testing.expectEqualStrings("A", p.tokens[0]);
    try std.testing.expectEqualStrings("bat", p.tokens[1]);
    try std.testing.expectEqualStrings("drew", p.tokens[2]);
    try std.testing.expectEqualStrings("a", p.tokens[3]);
    try std.testing.expectEqualStrings("cat", p.tokens[4]);
}
