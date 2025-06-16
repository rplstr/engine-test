const std = @import("std");
const vulkan = @import("vulkan");

/// Compile-time configurable application metadata.
pub const IDescription = struct {
    app_name: [:0]const u8 = "game",
    engine_name: [:0]const u8 = "engine",
    app_version: vulkan.Version = vulkan.makeApiVersion(0, 0, 1, 0),
    engine_version: vulkan.Version = vulkan.makeApiVersion(0, 0, 1, 0),
    api_version: vulkan.Version = vulkan.API_VERSION_1_3,
};

/// Opaque handle bundle returned by `createInstance`.
pub const IContext = struct {
    instance: vulkan.Instance,
    base: vulkan.BaseWrapper,
    wrapper: vulkan.InstanceWrapper,

    /// Always call this when the instance is no longer required.
    pub fn destroy(self: IContext) void {
        self.wrapper.destroyInstance(self.instance, null);
    }
};

/// Returns a fully initialised `Context` holding the instance and its
/// dispatch structures.
pub fn createInstance(
    loader: anytype,
    description: IDescription,
    comptime extensions: []const [:0]const u8,
    comptime layers: []const [:0]const u8,
) !IContext {
    const vkb = vulkan.BaseWrapper.load(loader);

    const ext_names = toPtrArray(extensions);
    const layer_names = toPtrArray(layers);

    var app_info = vulkan.ApplicationInfo{
        .s_type = .application_info,
        .p_next = null,
        .p_application_name = description.app_name,
        .application_version = @bitCast(description.app_version),
        .p_engine_name = description.engine_name,
        .engine_version = @bitCast(description.engine_version),
        .api_version = @bitCast(description.api_version),
    };

    const create_info = vulkan.InstanceCreateInfo{
        .s_type = .instance_create_info,
        .p_next = null,
        .flags = .{},
        .p_application_info = &app_info,
        .enabled_layer_count = @intCast(layer_names.len),
        .pp_enabled_layer_names = if (layer_names.len == 0) null else &layer_names,
        .enabled_extension_count = @intCast(ext_names.len),
        .pp_enabled_extension_names = if (ext_names.len == 0) null else &ext_names,
    };

    const instance_handle = try vkb.createInstance(&create_info, null);

    const vki = vulkan.InstanceWrapper.load(instance_handle, vkb.dispatch.vkGetInstanceProcAddr.?);

    return IContext{
        .instance = instance_handle,
        .base = vkb,
        .wrapper = vki,
    };
}

/// Same as createInstance, but consumes raw C arrays instead of comptime lists.
pub fn createInstanceRuntime(
    loader: vulkan.PfnGetInstanceProcAddr,
    settings: IDescription,
    ext_names: [*c]const [*:0]const u8,
    ext_cnt: usize,
    layer_names: [*c]const [*:0]const u8,
    layer_cnt: usize,
) !IContext {
    const vkb = vulkan.BaseWrapper.load(loader);

    var app_info = vulkan.ApplicationInfo{
        .s_type = .application_info,
        .p_next = null,
        .p_application_name = settings.app_name,
        .application_version = @bitCast(settings.app_version),
        .p_engine_name = settings.engine_name,
        .engine_version = @bitCast(settings.engine_version),
        .api_version = @bitCast(settings.api_version),
    };

    const ci = vulkan.InstanceCreateInfo{
        .s_type = .instance_create_info,
        .p_next = null,
        .flags = .{},
        .p_application_info = &app_info,
        .enabled_layer_count = @intCast(layer_cnt),
        .pp_enabled_layer_names = if (layer_cnt == 0) null else @ptrCast(layer_names),
        .enabled_extension_count = @intCast(ext_cnt),
        .pp_enabled_extension_names = if (ext_cnt == 0) null else @ptrCast(ext_names),
    };

    const handle = try vkb.createInstance(&ci, null);
    const vki = vulkan.InstanceWrapper.load(handle, vkb.dispatch.vkGetInstanceProcAddr.?);

    return IContext{ .instance = handle, .base = vkb, .wrapper = vki };
}

/// Convert a compile-time list of 0-terminated strings into the plain
/// C pointer array.
fn toPtrArray(comptime list: []const [:0]const u8) [list.len][*:0]const u8 {
    var out: [list.len][*:0]const u8 = undefined;
    inline for (list, 0..) |item, i| out[i] = item.ptr;
    return out;
}
