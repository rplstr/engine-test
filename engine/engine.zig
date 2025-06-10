const std = @import("std");

export fn engine_init(alloc: *std.mem.Allocator) callconv(.C) void {
    _ = alloc;
    std.debug.print("(engine) module_init\n", .{});
}

export fn engine_deinit() callconv(.C) void {
    std.debug.print("(engine) module_deinit\n", .{});
}

pub export fn print() callconv(.C) void {
    std.debug.print("engine_print\n", .{});
}
