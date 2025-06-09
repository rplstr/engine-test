const std = @import("std");
const engine = @import("engine");

pub export fn module_init() void {
    std.debug.print("(game) module_init\n", .{});
    engine.print();
}
