const std = @import("std");
const vulkan = @import("vulkan");

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
) callconv(.C) void {
    var vulkan_dl = std.DynLib.open("libvulkan.so") catch unreachable;
    const vkGetInstanceProcAddr = vulkan_dl.lookup(vulkan.PfnGetInstanceProcAddr, "vkGetInstanceProcAddr").?;

    const result = instance.createInstanceRuntime(vkGetInstanceProcAddr, settings.*, extensions, extension_count, layers, layer_count) catch return;
    out_ctx.* = result;
}

/// Destroy an instance.
///
/// C ABI. If calling from Zig, prefer `instance.IContext.destroy`.
pub export fn rendering_vulkan_destroy_instance(ctx: *IContext) callconv(.C) void {
    ctx.*.destroy();
}
