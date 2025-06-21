const std = @import("std");
const interface = @import("interface.zig");
const windowing = @import("windowing/interface.zig");
const host = @import("host");

extern const windowing_vtable: windowing.VTable;

const engine_vtable: interface.VTable = .{
    .windowing = &windowing_vtable,
};

pub export fn module_init(h: *const host.HostInterface) void {
    var pa = std.heap.page_allocator;
    windowing_vtable.init(&pa);
    h.register_interface(h.context, interface.iid_engine_v1, &engine_vtable);
}
