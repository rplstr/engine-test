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

pub const logical_device = @import("vulkan/logical_device.zig");
pub const LDDescription = logical_device.LDDescription;
pub const LDQueuePriorities = logical_device.LDQueuePriorities;
pub const LDDevice = logical_device.LDDevice;

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
/// Returns 0 on success or a negative error code.
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

/// Create a Vulkan logical device.
/// Returns 0 on success or a negative error code.
///
/// C ABI. If calling from Zig, prefer `logical_device.createLogicalDevice`.
pub export fn rendering_vulkan_create_logical_device(
    ctx: *const IInstance,
    physical: *const PDDevice,
    desc: *const LDDescription,
    extensions: [*c]const [*:0]const u8,
    extension_count: usize,
    out_device: *LDDevice,
) callconv(.C) c_int {
    const dev = logical_device.createLogicalDeviceRuntime(
        ctx.*,
        physical.*,
        desc.*,
        extensions,
        extension_count,
    ) catch |err| {
        return -@as(c_int, @intCast(@intFromError(err)));
    };
    out_device.* = dev;
    return 0;
}

/// Destroy a logical device.
///
/// C ABI. If calling from Zig, prefer `logical_device.LDDevice.destroy`.
pub export fn rendering_vulkan_destroy_logical_device(dev: *LDDevice) callconv(.C) void {
    if (dev.handle == null) return;
    dev.*.destroy();
    dev.* = undefined;
}

/// Returns a pointer to `vkGetInstanceProcAddr` exported by the loader.
pub fn getInstanceProcAddr() !vulkan.PfnGetInstanceProcAddr {
    try loader.init();
    const instanceProcAddr = try loader.get();
    return instanceProcAddr.fn_ptr;
}
