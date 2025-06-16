const std = @import("std");
const vulkan = @import("vulkan");
const loader = @import("vulkan/loader.zig");

pub const instance = @import("vulkan/instance.zig");
pub const IDescription = instance.IDescription;
pub const IContext = instance.IContext;

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
    out_ctx: *IContext,
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
/// C ABI. If calling from Zig, prefer `instance.IContext.destroy`.
pub export fn rendering_vulkan_destroy_instance(ctx: *IContext) callconv(.C) void {
    ctx.*.destroy();
}

/// Returns a pointer to `vkGetInstanceProcAddr` exported by the Vulkan loader.
pub fn getInstanceProcAddr() !vulkan.PfnGetInstanceProcAddr {
    try loader.init();
    const instanceProcAddr = try loader.get();
    return instanceProcAddr.fn_ptr;
}
