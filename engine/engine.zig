const std = @import("std");

pub const windowing = @import("windowing/window.zig");
pub const vulkan = @import("rendering/vulkan.zig");

export const engine_abi: u32 = 1;

var installPfn: *const fn (func: [*c]const u8, pfn: *const anyopaque) callconv(.c) bool = undefined;
var findPfn: *const fn (func: [*c]const u8) callconv(.c) ?*const anyopaque = undefined;

var vulkan_instance: ?vulkan.IContext = null;

export fn engine_init(
    allocator: *std.mem.Allocator,
    dispatcher: *const fn (func: [*c]const u8) callconv(.c) ?*const anyopaque,
) callconv(.c) void {
    _ = allocator;
    std.debug.print("(engine) module_init\n", .{});

    findPfn = @ptrCast(dispatcher);
    installPfn = @ptrCast(findPfn("installPfn").?);

    // windowing.init(allocator.*);

    _ = installPfn("w_open_window", &windowing.w_open_window);
    _ = installPfn("w_poll", &windowing.w_poll);
    _ = installPfn("w_close_window", &windowing.w_close_window);

    // VULKAN
    // INSTANCE
    const desc = vulkan.IDescription{};
    const ctx_res = vulkan.instance.createInstance(
        vulkan.vkGetInstanceProcAddr,
        desc,
        &[_][:0]const u8{},
        &[_][:0]const u8{},
    ) catch |err| {
        std.debug.print("failed to create instance {}\n", .{err});
        return;
    };
    vulkan_instance = ctx_res;
}

export fn engine_deinit() callconv(.c) void {
    std.debug.print("(engine) module_deinit\n", .{});

    // VULKAN
    // INSTANCE
    if (vulkan_instance) |*ctx_| {
        vulkan.rendering_vulkan_destroy_instance(ctx_);
        vulkan_instance = null;
    }
}

pub export fn print() callconv(.c) void {
    std.debug.print("engine_print\n", .{});
}
