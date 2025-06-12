const std = @import("std");
const engine = @import("engine");

var g_handle: u64 = 0;

export const game_abi: u32 = 1;

export fn game_init(allocator: *std.mem.Allocator) callconv(.C) void {
    _ = allocator;
    std.debug.print("(game) module_init\n", .{});
    g_handle = engine.windowing.w_open_window(&.{
        .width = 800,
        .height = 600,
        .title = "game",
    });
    if (g_handle == 0) {
        std.debug.print("failed to open window\n", .{});
        return;
    }
}

export fn game_update(dt: f64) callconv(.C) void {
    var ev: engine.windowing.WEvent = .{ .kind = .none, .code = 0 };

    while (engine.windowing.w_poll(g_handle, &ev)) {
        switch (ev.kind) {
            .close => {
                engine.windowing.w_close_window(g_handle);
                g_handle = 0;
            },
            .none => {},
        }
    }

    _ = dt;
}

export fn game_deinit() callconv(.C) void {
    if (g_handle != 0) {
        engine.windowing.w_close_window(g_handle);
        g_handle = 0;
    }
    std.debug.print("(game) module_deinit\n", .{});
}
