const std = @import("std");

pub export fn print() void {
    std.debug.print("engine_print\n", .{});
}

pub export fn engine_module_init() void {
    std.debug.print("(engine) module_init\n", .{});
}
