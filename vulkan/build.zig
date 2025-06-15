const std = @import("std");

pub fn module(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const vulkan_headers = b.dependency("vulkan_headers", .{});

    const vulkan_dependency = b.dependency("vulkan", .{
        .registry = vulkan_headers.path("registry/vk.xml"),
    });

    const vulkan_mod = vulkan_dependency.module("vulkan-zig");

    const mod = b.addModule("vulkan", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = vulkan_mod.root_source_file,
    });
    mod.addImport("vulkan_zig", vulkan_mod);

    const lib = b.addLibrary(.{
        .name = "vulkan_bindings",
        .root_module = mod,
        .linkage = .static,
    });

    return lib;
}
