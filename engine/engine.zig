const std = @import("std");

pub const windowing = @import("windowing/window.zig");

export const engine_abi: u32 = 1;

export fn engine_init(allocator: *std.mem.Allocator) callconv(.C) void {
    _ = allocator;
    std.debug.print("(engine) module_init\n", .{});
}

export fn engine_deinit() callconv(.C) void {
    std.debug.print("(engine) module_deinit\n", .{});
}

pub export fn print() callconv(.C) void {
    std.debug.print("engine_print\n", .{});
}
