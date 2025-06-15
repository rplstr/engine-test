const std = @import("std");
const engine = @import("engine");
const vk = @import("vulkan");

export const game_abi: u32 = 1;
var window: u64 = 0;

// TODO: split up this in multiple functions
export fn game_init(allocator: *std.mem.Allocator) callconv(.c) void {
    _ = allocator;
    window = engine.windowing.w_open_window(&.{
        .width = 800,
        .height = 600,
        .title = "game",
    });
}

export fn game_update(dt: f64) callconv(.c) bool {
    _ = dt;
    return true;
}

export fn game_deinit() callconv(.c) void {
    engine.windowing.w_close_window(window);
}
