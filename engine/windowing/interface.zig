const std = @import("std");

pub const Description = extern struct {
    width: u16,
    height: u16,
    title: ?[*:0]const u8,
};

pub const EventKind = enum(u8) {
    none,
    close,
};

pub const Event = extern struct {
    kind: EventKind,
    code: u32,
};

pub const VTable = extern struct {
    init: *const fn (allocator: *std.mem.Allocator) callconv(.c) void,
    open_window: *const fn (description: *const Description) callconv(.c) u64,
    poll: *const fn (out: *Event) callconv(.c) bool,
    close_window: *const fn (handle: u64) callconv(.c) void,
};
