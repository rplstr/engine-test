const std = @import("std");

pub export fn print() void {
    std.debug.print("engine_print\n", .{});
}

pub export fn engine_init() void {
    std.debug.print("(engine) init\n", .{});
}
