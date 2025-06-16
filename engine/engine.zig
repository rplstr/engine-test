const std = @import("std");
const proto = @import("proto");
const vk = @import("vulkan");

pub const windowing = @import("windowing/window.zig");
pub const vulkan = @import("rendering/vulkan.zig");

export const engine_abi: u32 = 1;

var vulkan_instance: ?vulkan.IContext = null;

export fn engine_init(
    allocator: *std.mem.Allocator,
    findPfn: proto.PfnFindPfn,
) callconv(.c) void {
    std.debug.print("(engine) module_init\n", .{});

    proto.loadRunner(findPfn) catch |err| {
        std.log.err("failed to load runner: {}", .{err});
        return;
    };
    proto.w_open_window = windowing.w_open_window;
    proto.w_poll = windowing.w_poll;
    proto.w_close_window = windowing.w_close_window;
    proto.installEngine();

    windowing.init(allocator.*);

    // VULKAN
    // INSTANCE
    const desc = vulkan.IDescription{};
    const ctx_res = vulkan.instance.createInstance(
        vulkan.getInstanceProcAddr() catch unreachable,
        desc,
        &[_][:0]const u8{},
        &[_][:0]const u8{},
    ) catch |err| {
        std.debug.print("failed to create instance {}\n", .{err});
        return;
    };
    vulkan_instance = ctx_res;
}

export fn engine_deinit() callconv(.c) void {
    std.debug.print("(engine) module_deinit\n", .{});

    // VULKAN
    // INSTANCE
    if (vulkan_instance) |*ctx| {
        vulkan.rendering_vulkan_destroy_instance(ctx);
        vulkan_instance = null;
    }
}

pub export fn print() callconv(.c) void {
    std.debug.print("engine_print\n", .{});
}
