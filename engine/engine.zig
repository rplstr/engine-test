const std = @import("std");

pub const windowing = @import("windowing/window.zig");
pub const vulkan = @import("rendering/vulkan.zig");

export const engine_abi: u32 = 1;

export fn engine_init(allocator: *std.mem.Allocator) callconv(.c) void {
    _ = allocator;
    std.debug.print("(engine) module_init\n", .{});
}

export fn engine_deinit() callconv(.c) void {
    std.debug.print("(engine) module_deinit\n", .{});
}

pub export fn print() callconv(.c) void {
    std.debug.print("engine_print\n", .{});
}
