const std = @import("std");
const engine = @import("engine");

export fn game_init(alloc: *std.mem.Allocator) callconv(.C) void {
    _ = alloc;
    std.debug.print("(game) module_init\n", .{});
    engine.print();
}

export fn game_deinit() callconv(.C) void {
    std.debug.print("(game) module_deinit\n", .{});
}
