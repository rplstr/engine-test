const std = @import("std");
const engine = @import("engine");

pub export fn game_init() void {
    std.debug.print("(game) init\n", .{});
    engine.print();
}
