const std = @import("std");
const vulkan = @import("vulkan");

const log = std.log.scoped(.physical_device);

pub const max_devices: u32 = 16;
pub const max_queue_families: u32 = 16;

/// Desired queue capabilities when selecting a physical device.
pub const PDRequirements = struct {
    graphics: bool = true,
    compute: bool = false,
    transfer: bool = false,
};

/// Indices of queue families that satisfy each capability.
/// A value of `std.math.maxInt(u32)` means the capability is unavailable.
pub const PDQueueInfo = struct {
    graphics: u32 = std.math.maxInt(u32),
    compute: u32 = std.math.maxInt(u32),
    transfer: u32 = std.math.maxInt(u32),
};

/// Snapshot of a physical device fulfilling the requested requirements.
pub const PDDevice = struct {
    handle: vulkan.PhysicalDevice,
    properties: vulkan.PhysicalDeviceProperties,
    features: vulkan.PhysicalDeviceFeatures,
    memory: vulkan.PhysicalDeviceMemoryProperties,
    queues: PDQueueInfo,
};

/// Helper responsible for enumerating physical devices and picking the best one.
pub const Selector = struct {
    instance: vulkan.Instance,
    wrapper: vulkan.InstanceWrapper,

    /// Pick the highest-scoring physical device that meets `req`.
    pub fn choose(self: Selector, req: PDRequirements) !PDDevice {
        log.debug("requirements are {}", .{req});
        var handles: [max_devices]vulkan.PhysicalDevice = undefined;
        const cnt = try enumerate(self, &handles);
        log.debug("enumerated total of {d} device(s)", .{cnt});

        var best_score: i32 = -2147483648;
        var best: PDDevice = undefined;
        var idx: usize = 0;
        while (idx < cnt) : (idx += 1) {
            const ctx = makeContext(self, handles[idx]);
            const s = scoreDevice(ctx, req);
            log.debug("device {d} with score of {d}", .{ idx, s });
            if (s > best_score) {
                best_score = s;
                best = ctx;
            }
        }
        if (best_score < 0) {
            log.err("no suitable physical device found meeting requested capabilities", .{});
            return error.NoSuitableDevice;
        }
        return best;
    }
};

fn enumerate(sel: Selector, out: *[max_devices]vulkan.PhysicalDevice) !usize {
    var cnt32: u32 = 0;
    _ = try sel.wrapper.enumeratePhysicalDevices(sel.instance, &cnt32, null);
    if (cnt32 == 0) {
        log.err("vkEnumeratePhysicalDevices returned zero devices", .{});
        return error.NoPhysicalDevice;
    }
    if (cnt32 > max_devices) cnt32 = max_devices;
    _ = try sel.wrapper.enumeratePhysicalDevices(sel.instance, &cnt32, out);
    log.debug("we have a total of {d} device(s)", .{cnt32});
    return cnt32;
}

fn makeContext(sel: Selector, dev: vulkan.PhysicalDevice) PDDevice {
    const props = sel.wrapper.getPhysicalDeviceProperties(dev);
    const feats = sel.wrapper.getPhysicalDeviceFeatures(dev);
    const mem = sel.wrapper.getPhysicalDeviceMemoryProperties(dev);

    return PDDevice{
        .handle = dev,
        .properties = props,
        .features = feats,
        .memory = mem,
        .queues = queryQueues(sel, dev),
    };
}

fn queryQueues(sel: Selector, dev: vulkan.PhysicalDevice) PDQueueInfo {
    var cnt32: u32 = 0;
    _ = sel.wrapper.getPhysicalDeviceQueueFamilyProperties(dev, &cnt32, null);
    if (cnt32 > max_queue_families) cnt32 = max_queue_families;

    var qprops: [max_queue_families]vulkan.QueueFamilyProperties = undefined;
    _ = sel.wrapper.getPhysicalDeviceQueueFamilyProperties(dev, &cnt32, &qprops);

    var qi = PDQueueInfo{};
    var i: u32 = 0;
    while (i < cnt32) : (i += 1) {
        const flags = qprops[i].queue_flags;
        if (flags.graphics_bit and qi.graphics == std.math.maxInt(u32)) qi.graphics = i;
        if (flags.compute_bit and qi.compute == std.math.maxInt(u32)) qi.compute = i;
        if (flags.transfer_bit and qi.transfer == std.math.maxInt(u32)) qi.transfer = i;
    }
    return qi;
}

fn scoreDevice(ctx: PDDevice, req: PDRequirements) i32 {
    var score: i32 = 0;
    switch (ctx.properties.device_type) {
        .discrete_gpu => score += 1000,
        .integrated_gpu => score += 100,
        else => {},
    }
    if (req.graphics and ctx.queues.graphics != std.math.maxInt(u32)) score += 100;
    if (req.compute and ctx.queues.compute != std.math.maxInt(u32)) score += 50;
    if (req.transfer and ctx.queues.transfer != std.math.maxInt(u32)) score += 25;
    log.debug("score={d}", .{score});
    return score;
}
