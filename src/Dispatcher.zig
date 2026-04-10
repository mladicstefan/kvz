const std = @import("std");
const expect = std.testing.expect;
const expectError = std.testing.expectError;

const Store = @import("Store.zig");

const Dispatcher = @This();
const HandlerFn = *const fn (tokens: [][]const u8, store: Store) void;

cmd_table: [16]u8,
handlers: [4]HandlerFn,

const MAX_CMD_LEN = 4;

// The computations of the @Vec masks for all CMD vecs will be done at compile time :)
const GET_VEC: @Vector(MAX_CMD_LEN, u8) = blk: {
    var buf = [_]u8{0} ** MAX_CMD_LEN; //pad with 0's
    buf[0] = 'g';
    buf[1] = 'e';
    buf[2] = 't';
    break :blk buf;
};

const SET_VEC: @Vector(MAX_CMD_LEN, u8) = blk: {
    var buf = [_]u8{0} ** MAX_CMD_LEN;
    buf[0] = 's';
    buf[1] = 'e';
    buf[2] = 't';
    break :blk buf;
};

const DEL_VEC: @Vector(MAX_CMD_LEN, u8) = blk: {
    var buf = [_]u8{0} ** MAX_CMD_LEN;
    buf[0] = 'd';
    buf[1] = 'e';
    buf[2] = 'l';
    break :blk buf;
};

const HANDLERS: [3]HandlerFn = .{ getHandler, putHandler, delHandler };

const DispatchError = error{
    UnknownCommand,
};

fn simdEqlCMDIgnoreCaseVec(a: []const u8, comptime b: @Vector(MAX_CMD_LEN, u8), comptime b_len: u8) bool {
    if (a.len != b_len) return false;
    if (a.len > MAX_CMD_LEN) return false;

    const comptime_mask: @Vector(MAX_CMD_LEN, u8) = @splat(0x20);
    const b_lowered: @Vector(MAX_CMD_LEN, u8) = comptime b | comptime_mask;

    var buf: [MAX_CMD_LEN]u8 = [_]u8{0} ** MAX_CMD_LEN;
    @memcpy(buf[0..a.len], a[0..a.len]);
    const vec: @Vector(MAX_CMD_LEN, u8) = buf;

    return @reduce(.And, (vec | comptime_mask) == b_lowered);
}

pub fn dispatch(tokens: [][]const u8, store: Store) DispatchError!void {
    const cmds = comptime .{
        .{ GET_VEC, 3, 0b0001 },
        .{ SET_VEC, 3, 0b0010 },
        .{ DEL_VEC, 3, 0b0100 },
    };

    var match_mask: u4 = 0;
    inline for (cmds) |cmd| {
        if (simdEqlCMDIgnoreCaseVec(tokens[0], cmd[0], cmd[1])) {
            match_mask |= cmd[2];
        }
    }

    if (match_mask == 0) return DispatchError.UnknownCommand;
    const index = @ctz(match_mask);
    HANDLERS[index](tokens, store);
}

fn getHandler(tokens: [][]const u8, store: Store) void {
    const val = store.get(tokens[1]);
    _ = val;
}
fn putHandler(tokens: [][]const u8, store: Store) void {
    const val = std.fmt.parseInt(u64, tokens[2], 10) catch return;
    store.put(tokens[1], val) catch return;
}
fn delHandler(tokens: [][]const u8, store: Store) void {
    _ = store.del(tokens[1]);
}
