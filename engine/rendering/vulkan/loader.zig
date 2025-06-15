const std = @import("std");
const builtin = @import("builtin");
const vulkan = @import("vulkan");

var vulkan_library: ?std.DynLib = null;
var instance_proc_addr: ?vulkan.PfnGetInstanceProcAddr = null;

/// Opaque handle to `vkGetInstanceProcAddr`.
pub const InstanceProcAddr = struct {
    fn_ptr: vulkan.PfnGetInstanceProcAddr,

    /// Wrapper.
    pub fn call(
        self: InstanceProcAddr,
        instance: vulkan.Instance,
        name: [*:0]const u8,
    ) ?vulkan.PfnVoidFunction {
        return self.fn_ptr(instance, name);
    }
};

/// Locate and retain the loader.
/// Multiple calls are idempotent.
pub fn init() !void {
    if (instance_proc_addr != null) return;

    const names = loaderNames();
    var err: ?anyerror = null;

    for (names) |name| {
        var lib = std.DynLib.open(name) catch |e| {
            if (e == null) err = e;
            continue;
        };

        const sym = lib.lookup(vulkan.PfnGetInstanceProcAddr, "vkGetInstanceProcAddr") catch |e| {
            if (e == null) err = e;
            lib.close();
            continue;
        };

        vulkan_library = lib;
        instance_proc_addr = InstanceProcAddr{ .fn_ptr = sym };
        return;
    }
    return err orelse error.VulkanLoaderUnavailable;
}

/// Retrieve the handle.
pub fn get() !InstanceProcAddr {
    if (instance_proc_addr) |proc_addr| return proc_addr;
    return error.VulkanLoaderUnavailable;
}

/// Unload the loader.
pub fn deinit() void {
    if (vulkan_library) |*lib| lib.close();
    vulkan_library = null;
    instance_proc_addr = null;
}

fn loaderNames() []const []const u8 {
    const unix = &[_][]const u8{ "libvulkan.so.1", "libvulkan.so" };
    const mac = &[_][]const u8{ "libvulkan.1.dylib", "libMoltenVK.dylib" };
    const win32 = &[_][]const u8{"vulkan-1.dll"};
    const none = &[_][]const u8{};

    return switch (builtin.os.tag) {
        .linux, .freebsd, .openbsd, .netbsd, .dragonfly => unix,
        .macos => mac,
        .windows => win32,
        else => none,
    };
}
