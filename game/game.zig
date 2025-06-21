const std = @import("std");
const engine = @import("engine");

extern const engine_vtable: engine.VTable;

pub export fn game_init(allocator: *std.mem.Allocator) callconv(.c) void {
    _ = allocator;

    const window_handle = engine_vtable.windowing.open_window(&.{
        .width = 1280,
        .height = 720,
        .title = "hi v-table",
    });

    if (window_handle == 0) {
        return;
    }
    defer engine_vtable.windowing.close_window(window_handle);

    var event: engine.windowing.Event = undefined;
    while (true) {
        if (engine_vtable.windowing.poll(&event)) {
            if (event.kind == .close) {
                break;
            }
        }
    }
}

pub export fn game_deinit() callconv(.c) void {}
