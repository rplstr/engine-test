const std = @import("std");
const vulkan = @import("vulkan");
const loader = @import("vulkan/loader.zig");

pub const instance = @import("vulkan/instance.zig");
pub const IDescription = instance.IDescription;
pub const IInstance = instance.IInstance;

pub const physical_device = @import("vulkan/physical_device.zig");
pub const PDRequirements = physical_device.PDRequirements;
pub const PDQueueInfo = physical_device.PDQueueInfo;
pub const PDDevice = physical_device.PDDevice;

/// Create a Vulkan instance.
/// Returns 0 on success or a negative error code.
///
/// C ABI. If calling from Zig, prefer `instance.createInstance`.
pub export fn rendering_vulkan_create_instance(
    settings: *const IDescription,
    extensions: [*c]const [*:0]const u8,
    extension_count: usize,
    layers: [*c]const [*:0]const u8,
    layer_count: usize,
    out_ctx: *IInstance,
) callconv(.C) c_int {
    const getInstanceProcAddrFn = getInstanceProcAddr() catch |err| {
        return -@as(c_int, @intCast(@intFromError(err)));
    };

    const result = instance.createInstanceRuntime(getInstanceProcAddrFn, settings.*, extensions, extension_count, layers, layer_count) catch |err| return {
        return -@as(c_int, @intCast(@intFromError(err)));
    };
    out_ctx.* = result;
    return 0;
}

/// Destroy an instance.
///
/// C ABI. If calling from Zig, prefer `instance.IInstance.destroy`.
pub export fn rendering_vulkan_destroy_instance(ctx: *IInstance) callconv(.C) void {
    ctx.*.destroy();
}

/// Select a physical device that meets the given `requirements`.
/// Returns 0 on success, otherwise a negative Zig error code.
///
/// C ABI. If calling from Zig, prefer `instance.Selector.choose`.
pub export fn rendering_vulkan_choose_physical_device(
    ctx: *const IInstance,
    requirements: *const PDRequirements,
    out_device: *PDDevice,
) callconv(.C) c_int {
    var sel = physical_device.Selector{ .instance = ctx.*.instance, .wrapper = ctx.*.wrapper };
    const dev = sel.choose(requirements.*) catch |err| {
        return -@as(c_int, @intCast(@intFromError(err)));
    };
    out_device.* = dev;
    return 0;
}

/// Returns a pointer to `vkGetInstanceProcAddr` exported by the Vulkan loader.
pub fn getInstanceProcAddr() !vulkan.PfnGetInstanceProcAddr {
    try loader.init();
    const instanceProcAddr = try loader.get();
    return instanceProcAddr.fn_ptr;
}
