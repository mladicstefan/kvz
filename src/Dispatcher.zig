const std = @import("std");
const expect = std.testing.expect;
const expectError = std.testing.expectError;

const Store = @import("Store.zig");

const Dispatcher = @This();
const HandlerFn = *const fn (tokens: [][]const u8, store: *Store) void;

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

const LS_VEC: @Vector(MAX_CMD_LEN, u8) = blk: {
    var buf = [_]u8{0} ** MAX_CMD_LEN;
    buf[0] = 'l';
    buf[1] = 's';
    break :blk buf;
};

const HANDLERS: [4]HandlerFn = .{ getHandler, setHandler, delHandler, lsHandler };

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

pub fn dispatch(tokens: [][]const u8, store: *Store) DispatchError!void {
    const cmds = comptime .{
        .{ GET_VEC, 3, 0b0001 },
        .{ SET_VEC, 3, 0b0010 },
        .{ DEL_VEC, 3, 0b0100 },
        .{ LS_VEC, 2, 0b1000 },
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

fn getHandler(tokens: [][]const u8, store: *Store) void {
    const val = store.get(tokens[1]);
    _ = val; // TODO: write val to response buffer
}

fn setHandler(tokens: [][]const u8, store: *Store) void {
    store.set(tokens[1], tokens[2]);
    // TODO: write OK to response buffer
}

fn delHandler(tokens: [][]const u8, store: *Store) void {
    store.del(tokens[1]);
    // TODO: write OK to response buffer
}

fn lsHandler(tokens: [][]const u8, store: *Store) void {
    _ = tokens;
    store.ls();
}

// =================================
// tests below with mock functions, safe to ignore, will be deleted
// =================================

fn mockGet(ptr: *anyopaque, key: []const u8) ?[]const u8 {
    _ = ptr;
    _ = key;
    return null;
}

fn mockSet(ptr: *anyopaque, key: []const u8, val: []const u8) void {
    _ = ptr;
    _ = key;
    _ = val;
}

fn mockDel(ptr: *anyopaque, key: []const u8) void {
    _ = ptr;
    _ = key;
}

fn mockLs(ptr: *anyopaque) void {
    _ = ptr;
}

fn mockStore() Store {
    return .{
        .ptr = undefined, // ptr is fine as undefined since mock fns ignore it
        .getFn = mockGet,
        .setFn = mockSet,
        .delFn = mockDel,
        .lsFn = mockLs,
    };
}

test "dispatch GET lowercase" {
    var mock_store: Store = mockStore();
    var tokens = [_][]const u8{ "get", "somekey" };
    try dispatch(&tokens, &mock_store);
}

test "dispatch GET uppercase" {
    var mock_store: Store = mockStore();
    var tokens = [_][]const u8{ "GET", "somekey" };
    try dispatch(&tokens, &mock_store);
}

test "dispatch GET mixed case" {
    var mock_store: Store = mockStore();
    var tokens = [_][]const u8{ "Get", "somekey" };
    try dispatch(&tokens, &mock_store);
}

test "dispatch SET" {
    var mock_store: Store = mockStore();
    var tokens = [_][]const u8{ "SET", "somekey", "someval" };
    try dispatch(&tokens, &mock_store);
}

test "dispatch DEL" {
    var mock_store: Store = mockStore();
    var tokens = [_][]const u8{ "DEL", "somekey" };
    try dispatch(&tokens, &mock_store);
}

test "dispatch LS" {
    var mock_store: Store = mockStore();
    var tokens = [_][]const u8{"LS"};
    try dispatch(&tokens, &mock_store);
}

test "dispatch LS lowercase" {
    var mock_store: Store = mockStore();
    var tokens = [_][]const u8{"ls"};
    try dispatch(&tokens, &mock_store);
}

test "dispatch unknown command returns error" {
    var mock_store: Store = mockStore();
    var tokens = [_][]const u8{"FOO"};
    try expectError(DispatchError.UnknownCommand, dispatch(&tokens, &mock_store));
}

test "dispatch empty string returns error" {
    var mock_store: Store = mockStore();
    var tokens = [_][]const u8{""};
    try expectError(DispatchError.UnknownCommand, dispatch(&tokens, &mock_store));
}

test "dispatch too long returns error" {
    var mock_store: Store = mockStore();
    var tokens = [_][]const u8{"SETX"};
    try expectError(DispatchError.UnknownCommand, dispatch(&tokens, &mock_store));
}
