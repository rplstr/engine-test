const std = @import("std");
const engine = @import("engine");
const vk = @import("vulkan");

var window: u64 = 0;

export const game_abi: u32 = 1;

var installPfn: *const fn (func: [*c]const u8, pfn: *const anyopaque) callconv(.c) bool = undefined;
var findPfn: *const fn (func: [*c]const u8) callconv(.c) ?*const anyopaque = undefined;
var w_open_window: *const @TypeOf(engine.windowing.w_open_window) = undefined;
var w_poll: *const @TypeOf(engine.windowing.w_poll) = undefined;
var w_close_window: *const @TypeOf(engine.windowing.w_close_window) = undefined;

export fn game_init(
    allocator: *std.mem.Allocator,
    dispatcher: *const fn (func: [*c]const u8) callconv(.c) ?*const anyopaque,
) callconv(.c) void {
    _ = allocator;
    std.debug.print("(game) module_init\n", .{});

    findPfn = @ptrCast(dispatcher);
    installPfn = @ptrCast(findPfn("installPfn").?);
    w_open_window = @ptrCast(findPfn("w_open_window").?);
    w_poll = @ptrCast(findPfn("w_poll").?);
    w_close_window = @ptrCast(findPfn("w_close_window").?);

    window = w_open_window(&.{
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

    var ev: engine.windowing.WEvent = .{ .kind = .none, .code = 0 };
    while (w_poll(&ev)) switch (ev.kind) {
        .close => {
            w_close_window(window);
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
        w_close_window(window);
        window = 0;
    }
    std.debug.print("(game) module_deinit\n", .{});
}
