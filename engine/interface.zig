const std = @import("std");

pub const windowing = @import("windowing/interface.zig");

pub const VTable = extern struct {
    windowing: *const windowing.VTable,
};
