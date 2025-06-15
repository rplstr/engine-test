const std = @import("std");
const proto = @import("proto");

var window: u64 = 0;

export const game_abi: u32 = 1;

export fn game_init(
    allocator: *std.mem.Allocator,
    findPfn: proto.PfnFindPfn,
) callconv(.c) void {
    _ = allocator;
    std.debug.print("(game) module_init\n", .{});

    proto.loadRunner(findPfn) catch |err| {
        std.log.err("failed to load runner: {}", .{err});
        return;
    };
    proto.loadEngine() catch |err| {
        std.log.err("failed to load engine: {}", .{err});
        return;
    };

    window = proto.w_open_window(&.{
        .width = 800,
        .height = 600,
        .title = "game",
    });
    if (window == 0) {
        std.debug.print("failed to open window\n", .{});
        return;
    }
}

export fn game_update(dt: f64) callconv(.c) bool {
    if (window == 0) return false;

    var ev: proto.WEvent = .{ .kind = .none, .code = 0 };
    while (proto.w_poll(&ev)) switch (ev.kind) {
        .close => {
            proto.w_close_window(window);
            window = 0;
            return false;
        },
        else => {},
    };

    _ = dt;
    return true;
}

export fn game_deinit() callconv(.c) void {
    if (window != 0) {
        proto.w_close_window(window);
        window = 0;
    }
    std.debug.print("(game) module_deinit\n", .{});
}
