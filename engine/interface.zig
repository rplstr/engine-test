const std = @import("std");

pub const windowing = @import("windowing/interface.zig");

pub const iid_engine_v1 = std.hash.Fnv1a_64.hash("engineV1");

pub const VTable = extern struct {
    windowing: *const windowing.VTable,
};
