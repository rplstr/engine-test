const std = @import("std");
const interface = @import("interface.zig");
const windowing = @import("windowing/interface.zig");

extern const windowing_vtable: windowing.VTable;

pub export const engine_vtable: interface.VTable = .{
    .windowing = &windowing_vtable,
};

pub export fn engine_init(allocator: *std.mem.Allocator) callconv(.c) void {
    windowing_vtable.init(allocator);
}

pub export fn engine_deinit() callconv(.c) void {}
