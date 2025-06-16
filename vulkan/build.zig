const std = @import("std");

pub fn module(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const vulkan_headers = b.dependency("vulkan_headers", .{});

    const vulkan_dependency = b.dependency("vulkan", .{
        .registry = vulkan_headers.path("registry/vk.xml"),
    });

    const mod = vulkan_dependency.module("vulkan-zig");
    mod.optimize = optimize;
    mod.resolved_target = target;

    return mod;
}
