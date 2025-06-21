const std = @import("std");
const engine = @import("engine");
const host = @import("host");

var vtable: *const engine.VTable = undefined;

pub export fn attach(h: *const host.HostInterface) void {
    const engine_ptr = h.query_interface(h.context, engine.iid_engine_v1) orelse {
        std.log.err("failed to get engine interface", .{});
        return;
    };

    vtable = @ptrCast(@alignCast(engine_ptr));

    const window_handle = vtable.windowing.open_window(&.{
        .width = 1280,
        .height = 720,
        .title = "hi v-table",
    });

    if (window_handle == 0) {
        return;
    }
    defer vtable.windowing.close_window(window_handle);

    var event: engine.windowing.Event = undefined;
    while (true) {
        if (vtable.windowing.poll(&event)) {
            if (event.kind == .close) {
                break;
            }
        }
    }
}
