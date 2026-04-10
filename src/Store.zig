pub const Store = @This();
ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    getFn: *const fn (ptr: *anyopaque, key: []const u8) ?u64,
    putFn: *const fn (ptr: *anyopaque, key: []const u8, val: u64) error{OutOfMemory}!void,
    delFn: *const fn (ptr: *anyopaque, key: []const u8) bool,
};

pub fn get(self: Store, key: []const u8) ?u64 {
    return self.vtable.getFn(self.ptr, key);
}

pub fn put(self: Store, key: []const u8, val: u64) error{OutOfMemory}!void {
    return self.vtable.putFn(self.ptr, key, val);
}

pub fn del(self: Store, key: []const u8) bool {
    return self.vtable.delFn(self.ptr, key);
}
