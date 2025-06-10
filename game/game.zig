const std = @import("std");
const engine = @import("engine");
const c = @cImport({
    @cInclude("windows.h");
});

export fn game_init(alloc: *std.mem.Allocator) callconv(.C) void {
    _ = alloc;
    std.debug.print("(game) module_init\n", .{});
    hi();
    engine.print();
}

export fn game_deinit() callconv(.C) void {
    std.debug.print("(game) module_deinit\n", .{});
}

pub fn hi() void {
    _ = c.MessageBoxA(null, "hello!", "game module", 0);
}
