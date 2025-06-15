const std = @import("std");
const engine = @import("engine");
const vk = @import("vulkan");

var window: u64 = 0;
var vulkan_instance: ?engine.vulkan.IContext = null;

export const game_abi: u32 = 1;

// TODO: split up this in multiple functions
export fn game_init(allocator: *std.mem.Allocator) callconv(.c) void {
    _ = allocator;
    std.debug.print("(game) module_init\n", .{});

    // WINDOW
    window = engine.windowing.w_open_window(&.{
        .width = 800,
        .height = 600,
        .title = "game",
    });
    if (window == 0) {
        std.debug.print("failed to open window\n", .{});
        return;
    }

    // VULKAN
    // INSTANCE
    const desc = engine.vulkan.IDescription{};
    const ctx_res = engine.vulkan.instance.createInstance(
        engine.vulkan.vkGetInstanceProcAddr,
        desc,
        &[_][:0]const u8{},
        &[_][:0]const u8{},
    ) catch |err| {
        std.debug.print("failed to create instance {}\n", .{err});
        return;
    };
    vulkan_instance = ctx_res;
}

export fn game_update(dt: f64) callconv(.c) bool {
    if (window == 0) return false;

    var ev: engine.windowing.WEvent = .{ .kind = .none, .code = 0 };
    while (engine.windowing.w_poll(&ev)) switch (ev.kind) {
        .close => {
            engine.windowing.w_close_window(window);
            window = 0;
            return false;
        },
        else => {},
    };

    _ = dt;
    return true;
}

export fn game_deinit() callconv(.c) void {
    // VULKAN
    // INSTANCE
    if (vulkan_instance) |*ctx_| {
        engine.vulkan.rendering_vulkan_destroy_instance(ctx_);
        vulkan_instance = null;
    }

    // WINDOW
    if (window != 0) {
        engine.windowing.w_close_window(window);
        window = 0;
    }
    std.debug.print("(game) module_deinit\n", .{});
}
