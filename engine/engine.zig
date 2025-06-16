const std = @import("std");
const proto = @import("proto");
const vk = @import("vulkan");

pub const windowing = @import("windowing/window.zig");
pub const vulkan = @import("rendering/vulkan.zig");

export const engine_abi: u32 = 1;

var vulkan_instance: ?vulkan.IInstance = null;
var vulkan_device: ?vulkan.LDDevice = null;

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

    // PHYSICAL DEVICE
    var selector = vulkan.physical_device.Selector{ .instance = ctx_res.instance, .wrapper = ctx_res.wrapper };
    const pd = selector.choose(.{}) catch |err| {
        std.debug.print("failed to choose physical device: {}\n", .{err});
        return;
    };
    std.debug.print("using device {s}\n", .{pd.properties.device_name});
    // LOGICAL DEVICE
    const dev_desc = vulkan.LDDescription{};
    const device = vulkan.logical_device.createLogicalDevice(
        ctx_res,
        pd,
        dev_desc,
        &[_][:0]const u8{},
    ) catch |err| {
        std.debug.print("failed to create logical device: {}\n", .{err});
        return;
    };

    vulkan_device = device;
    vulkan_instance = ctx_res;
}

export fn engine_deinit() callconv(.c) void {
    std.debug.print("(engine) module_deinit\n", .{});

    // VULKAN
    // DEVICE
    if (vulkan_device) |*dev| {
        dev.destroy();
        vulkan_device = null;
    }

    // INSTANCE
    if (vulkan_instance) |*ctx| {
        vulkan.rendering_vulkan_destroy_instance(ctx);
        vulkan_instance = null;
    }
}

pub export fn print() callconv(.c) void {
    std.debug.print("engine_print\n", .{});
}
