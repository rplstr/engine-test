const std = @import("std");
const engine = @import("engine");

var handle: u64 = 0;

export const game_abi: u32 = 1;

export fn game_init(allocator: *std.mem.Allocator) callconv(.c) void {
    _ = allocator;
    std.debug.print("(game) module_init\n", .{});
    handle = engine.windowing.w_open_window(&.{
        .width = 800,
        .height = 600,
        .title = "game",
    });
    if (handle == 0) {
        std.debug.print("failed to open window\n", .{});
        return;
    }
}

export fn game_update(dt: f64) callconv(.c) bool {
    if (handle == 0) return false;

    var ev: engine.windowing.WEvent = .{ .kind = .none, .code = 0 };
    while (engine.windowing.w_poll(&ev)) switch (ev.kind) {
        .close => {
            engine.windowing.w_close_window(handle);
            handle = 0;
            return false;
        },
        else => {},
    };

    _ = dt;
    return true;
}

export fn game_deinit() callconv(.c) void {
    if (handle != 0) {
        engine.windowing.w_close_window(handle);
        handle = 0;
    }
    std.debug.print("(game) module_deinit\n", .{});
}
