const std = @import("std");
const vulkan = @import("vulkan");

const instance_mod = @import("instance.zig");
const physical_mod = @import("physical_device.zig");
const log = std.log.scoped(.logical_device);

/// Queue priorities for each queue family.
pub const LDQueuePriorities = struct {
    graphics: f32 = 1.0,
    compute: f32 = 1.0,
    transfer: f32 = 1.0,
};

/// Immutable description of the logical device to create.
pub const LDDescription = struct {
    features: vulkan.PhysicalDeviceFeatures = .{},
    priorities: LDQueuePriorities = .{},

    /// Converts a comptime list of 0-terminated UTF-8 extension names into
    /// the contiguous C array.
    pub fn extSlice(comptime list: []const [:0]const u8) [list.len][*:0]const u8 {
        var out: [list.len][*:0]const u8 = undefined;
        inline for (list, 0..) |s, i| out[i] = s.ptr;
        return out;
    }
};

/// Bundled logical-device handle returned by `createLogicalDevice`.
pub const LDDevice = struct {
    handle: ?vulkan.Device,
    wrapper: vulkan.DeviceWrapper,
    graphics_queue: ?vulkan.Queue = null,
    compute_queue: ?vulkan.Queue = null,
    transfer_queue: ?vulkan.Queue = null,

    /// Destroys the wrapped `VkDevice`.
    pub fn destroy(self: LDDevice) void {
        if (self.handle) |handle| {
            log.debug("destroying device with handle of {x}", .{handle});
            self.wrapper.destroyDevice(handle, null);
        }
    }
};

/// Creates a logical device from `physical_device`.
pub fn createLogicalDevice(
    instance: instance_mod.IInstance,
    physical_device: physical_mod.PDDevice,
    description: LDDescription,
    comptime extensions: []const [:0]const u8,
) !LDDevice {
    const dev_ext_names = LDDescription.extSlice(extensions);
    log.debug("ext_count={d}", .{dev_ext_names.len});
    const queues = buildQueues(physical_device, description.priorities);

    const dc_info = vulkan.DeviceCreateInfo{
        .s_type = .device_create_info,
        .p_next = null,
        .flags = .{},
        .queue_create_info_count = queues.count,
        .p_queue_create_infos = &queues.list,
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = null,
        .enabled_extension_count = @intCast(dev_ext_names.len),
        .pp_enabled_extension_names = if (dev_ext_names.len == 0) null else &dev_ext_names,
        .p_enabled_features = &description.features,
    };

    return initDevice(instance, physical_device, dc_info);
}

/// Same as `createLogicalDevice`, but consumes raw C arrays instead of comptime lists.
pub fn createLogicalDeviceRuntime(
    instance: instance_mod.IInstance,
    physical_device: physical_mod.PDDevice,
    description: LDDescription,
    ext_names: [*c]const [*:0]const u8,
    ext_count: usize,
) !LDDevice {
    log.debug("ext_count={d}", .{ext_count});
    const queues = buildQueues(physical_device, description.priorities);

    const dc_info = vulkan.DeviceCreateInfo{
        .s_type = .device_create_info,
        .p_next = null,
        .flags = .{},
        .queue_create_info_count = queues.count,
        .p_queue_create_infos = &queues.list,
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = null,
        .enabled_extension_count = @intCast(ext_count),
        .pp_enabled_extension_names = if (ext_count == 0) null else @ptrCast(ext_names),
        .p_enabled_features = &description.features,
    };

    return initDevice(instance, physical_device, dc_info);
}

inline fn pushQueueCreateInfo(
    list: *[3]vulkan.DeviceQueueCreateInfo,
    pri_storage: *[3][1]f32,
    cnt: *u32,
    family: u32,
    priority: f32,
) void {
    if (family == std.math.maxInt(u32)) {
        log.warn("family invalid, skipping", .{});
        return;
    }

    var i: u32 = 0;

    log.debug("checking duplicates in existing {d} entries", .{cnt.*});
    while (i < cnt.*) : (i += 1) {
        if (list.*[i].queue_family_index == family) return;
    }

    pri_storage.*[cnt.*][0] = priority;
    list.*[cnt.*] = .{
        .s_type = .device_queue_create_info,
        .p_next = null,
        .flags = .{},
        .queue_family_index = family,
        .queue_count = 1,
        .p_queue_priorities = &pri_storage.*[cnt.*],
    };
    log.debug("added as idx={d}", .{cnt.*});
    cnt.* += 1;
}

fn initDevice(
    instance: instance_mod.IInstance,
    physical_device: physical_mod.PDDevice,
    create_info: vulkan.DeviceCreateInfo,
) !LDDevice {
    const handle = try instance.wrapper.createDevice(physical_device.handle, &create_info, null);
    const dev_wrap = vulkan.DeviceWrapper.load(handle, instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
    log.debug("created device handle={x}", .{handle});

    var out = LDDevice{ .handle = handle, .wrapper = dev_wrap };
    if (physical_device.queues.graphics != std.math.maxInt(u32))
        out.graphics_queue = dev_wrap.getDeviceQueue(handle, physical_device.queues.graphics, 0);
    if (physical_device.queues.compute != std.math.maxInt(u32))
        out.compute_queue = dev_wrap.getDeviceQueue(handle, physical_device.queues.compute, 0);
    if (physical_device.queues.transfer != std.math.maxInt(u32))
        out.transfer_queue = dev_wrap.getDeviceQueue(handle, physical_device.queues.transfer, 0);
    return out;
}

fn buildQueues(pd: physical_mod.PDDevice, prio: LDQueuePriorities) struct { list: [3]vulkan.DeviceQueueCreateInfo, count: u32 } {
    var pri_storage: [3][1]f32 = undefined;
    var list: [3]vulkan.DeviceQueueCreateInfo = undefined;
    var cnt: u32 = 0;

    pushQueueCreateInfo(&list, &pri_storage, &cnt, pd.queues.graphics, prio.graphics);
    pushQueueCreateInfo(&list, &pri_storage, &cnt, pd.queues.compute, prio.compute);
    pushQueueCreateInfo(&list, &pri_storage, &cnt, pd.queues.transfer, prio.transfer);

    log.debug("produced {d} queue CIs", .{cnt});
    return .{ .list = list, .count = cnt };
}
