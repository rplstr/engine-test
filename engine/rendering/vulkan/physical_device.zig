const std = @import("std");
const vulkan = @import("vulkan");

const max_devices = 16;
const max_families = 16;
const max_extensions = 64;
const invalid_index = 0xffffffff;

/// Device–level queue family indices relevant to the engine.
pub const DQueueFamilies = struct {
    graphics: u32 = invalid_index,
    compute: u32 = invalid_index,
    transfer: u32 = invalid_index,
    present: u32 = invalid_index,

    pub fn isComplete(self: DQueueFamilies, need_present: bool) bool {
        return self.graphics != invalid_index and (!need_present or self.present != invalid_index);
    }
};

/// Immutable description of the chosen physical device.
pub const DDevice = struct {
    device: vulkan.PhysicalDevice,
    properties: vulkan.PhysicalDeviceProperties,
    memory: vulkan.PhysicalDeviceMemoryProperties,
    queues: DQueueFamilies,
};

/// Pick the best-suited physical device for the given instance/surface.
pub fn init(
    proxy: vulkan.InstanceProxy,
    surface: ?vulkan.SurfaceKHR,
) !DDevice {
    const pd = try choose(proxy, surface);
    const props = proxy.getPhysicalDeviceProperties(pd);
    const mem = proxy.getPhysicalDeviceMemoryProperties(pd);
    const q_fam = try discoverQueues(proxy, pd, surface);

    return .{ .device = pd, .properties = props, .memory = mem, .queues = q_fam };
}

fn choose(proxy: vulkan.InstanceProxy, surface: ?vulkan.SurfaceKHR) !vulkan.PhysicalDevice {
    var cnt: u32 = 0;
    _ = try proxy.enumeratePhysicalDevices(&cnt, null);
    if (cnt == 0) return error.NoPhysicalDeviceFound;
    if (cnt > max_devices) cnt = max_devices;

    var handles: [max_devices]vulkan.PhysicalDevice = undefined;
    _ = try proxy.enumeratePhysicalDevices(&cnt, &handles);

    var best: ?vulkan.PhysicalDevice = null;
    var best_score: u32 = 0;
    for (handles[0..cnt]) |pd| {
        if (!checkExtensions(proxy, pd)) continue;
        const queues = try discoverQueues(proxy, pd, surface);
        if (!queues.isComplete(surface != null)) continue;
        const score = scoreDevice(proxy, pd);
        if (score > best_score) {
            best = pd;
            best_score = score;
        }
    }
    return best orelse error.NoSuitablePhysicalDevice;
}

fn scoreDevice(proxy: vulkan.InstanceProxy, pd: vulkan.PhysicalDevice) u32 {
    const props = proxy.getPhysicalDeviceProperties(pd);
    var score: u32 = 0;
    if (props.device_type == .discrete_gpu) score += 1_000;
    score += props.limits.max_image_dimension_2d;
    return score;
}

fn checkExtensions(proxy: vulkan.InstanceProxy, pd: vulkan.PhysicalDevice) bool {
    var cnt: u32 = 0;
    _ = proxy.enumerateDeviceExtensionProperties(pd, null, &cnt, null) catch return false;
    if (cnt == 0) return false;
    if (cnt > max_extensions) cnt = max_extensions;

    var props: [max_extensions]vulkan.ExtensionProperties = undefined;
    _ = proxy.enumerateDeviceExtensionProperties(pd, null, &cnt, &props) catch return false;

    inline for ([_][:0]const u8{}) |req| {
        if (!extensionSupported(req, props[0..cnt])) return false;
    }
    return true;
}

fn extensionSupported(name: [:0]const u8, list: []const vulkan.ExtensionProperties) bool {
    for (list) |p| if (std.mem.eql(u8, std.mem.span(name.ptr), std.mem.sliceTo(&p.extension_name, 0))) {
        return true;
    };
    return false;
}

fn discoverQueues(
    proxy: vulkan.InstanceProxy,
    pd: vulkan.PhysicalDevice,
    surface: ?vulkan.SurfaceKHR,
) !DQueueFamilies {
    var cnt: u32 = 0;
    proxy.getPhysicalDeviceQueueFamilyProperties(pd, &cnt, null);
    if (cnt > max_families) cnt = max_families;

    var props: [max_families]vulkan.QueueFamilyProperties = undefined;
    proxy.getPhysicalDeviceQueueFamilyProperties(pd, &cnt, &props);

    var out = DQueueFamilies{};
    var i: u32 = 0;
    while (i < cnt) : (i += 1) {
        const flags = props[i].queue_flags;
        if (out.graphics == invalid_index and flags.graphics_bit) out.graphics = i;
        if (out.compute == invalid_index and flags.compute_bit) out.compute = i;
        if (out.transfer == invalid_index and flags.transfer_bit) out.transfer = i;

        if (surface != null and out.present == invalid_index) {
            if ((try proxy.getPhysicalDeviceSurfaceSupportKHR(pd, i, surface.?)) == vulkan.TRUE) {
                out.present = i;
            }
        }
    }
    return out;
}
