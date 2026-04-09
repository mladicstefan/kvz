pub const Store = @This();
ptr: *anyopaque,
getFn: *const fn (ptr: *anyopaque, key: []const u8) ?[]const u8,
setFn: *const fn (ptr: *anyopaque, key: []const u8, val: []const u8) void,
delFn: *const fn (ptr: *anyopaque, key: []const u8) void,
lsFn: *const fn (ptr: *anyopaque) void,

// ergonomic wrappers so handlers don't call .getFn directly
pub fn get(self: Store, key: []const u8) ?[]const u8 {
    return self.getFn(self.ptr, key);
}
pub fn set(self: Store, key: []const u8, val: []const u8) void {
    self.setFn(self.ptr, key, val);
}
pub fn del(self: Store, key: []const u8) void {
    self.delFn(self.ptr, key);
}
pub fn ls(self: Store) void {
    self.lsFn(self.ptr);
}
