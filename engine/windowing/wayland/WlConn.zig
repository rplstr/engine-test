const std = @import("std");
const c = @cImport({
    @cInclude("wayland.h");
    @cInclude("xdg-shell.h");
});

const log = std.log.scoped(.wayland);

allocator: std.mem.Allocator,

display: *c.struct_wl_display = undefined,
registry: *c.struct_wl_registry = undefined,

closed: bool = false,

compositor: ?*c.struct_wl_compositor = null,
shm: ?*c.struct_wl_shm = null,
xdg_wm_base: ?*c.struct_xdg_wm_base = null,

pub fn init(allocator: std.mem.Allocator) !*@This() {
    const self = try allocator.create(@This());
    errdefer allocator.destroy(self);
    self.* = .{ .allocator = allocator };

    self.display = c.wl_display_connect(null) orelse {
        log.err("unable to establish Wayland display connection", .{});
        return error.FailedToConnect;
    };
    errdefer c.wl_display_disconnect(self.display);

    self.registry = c.wl_display_get_registry(self.display) orelse {
        log.err("wl_registry interface not available on display", .{});
        return error.MissingRegistry;
    };
    errdefer c.wl_registry_destroy(self.registry);

    _ = c.wl_registry_add_listener(
        self.registry,
        &registry_listener,
        self,
    );

    _ = c.wl_display_roundtrip(self.display);

    if (self.compositor == null or
        self.shm == null or
        self.xdg_wm_base == null)
    {
        log.err("failed to obtain essential global interfaces (wl_compositor, wl_shm, xdg_wm_base)", .{});
        return error.MissingGlobals;
    }

    _ = c.xdg_wm_base_add_listener(
        self.xdg_wm_base.?,
        &xdg_wm_base_listener,
        self,
    );

    return self;
}

pub fn deinit(self: *@This()) void {
    if (self.xdg_wm_base) |xdg_wm_base|
        c.xdg_wm_base_destroy(xdg_wm_base);

    if (self.shm) |shm|
        c.wl_shm_destroy(shm);

    if (self.compositor) |compositor|
        c.wl_compositor_destroy(compositor);

    c.wl_region_destroy(self.registry);

    c.wl_display_disconnect(self.display);

    self.allocator.destroy(self);
}

fn tryBindInterface(
    self: *@This(),
    comptime field: []const u8,
    interface: [*c]const u8,
    name: u32,
    expected_interface: *const c.struct_wl_interface,
    wanted_version: u32,
) void {
    if (!std.mem.eql(u8, std.mem.span(interface), std.mem.span(expected_interface.name)))
        return;

    log.debug("found {s}", .{field});

    if (@field(self, field) != null) {
        log.warn("found duplicate {s}", .{field});
        return;
    }

    log.debug("bind(\n\t{*},\n\t{},\n\t{},\n\t{},\n)", .{
        self.registry,
        name,
        &expected_interface,
        wanted_version,
    });
    const result = c.wl_registry_bind(
        self.registry,
        name,
        expected_interface,
        wanted_version,
    ) orelse {
        log.err("failed to bind interface", .{});
        return;
    };

    @field(self, field) = @alignCast(@ptrCast(result));
}

fn registry_handle_global(
    data: ?*anyopaque,
    registry: ?*c.struct_wl_registry,
    name: u32,
    interface: [*c]const u8,
    version: u32,
) callconv(.c) void {
    const self: *@This() = @alignCast(@ptrCast(data.?));
    std.debug.assert(self.registry == registry);

    log.debug("interface: {s}, version: {}, name: {d}", .{ interface, version, name });

    self.tryBindInterface(
        "compositor",
        interface,
        name,
        &c.wl_compositor_interface,
        4,
    );

    self.tryBindInterface(
        "shm",
        interface,
        name,
        &c.wl_shm_interface,
        1,
    );

    self.tryBindInterface(
        "xdg_wm_base",
        interface,
        name,
        &c.xdg_wm_base_interface,
        1,
    );
}

fn registry_handle_global_remove(
    data: ?*anyopaque,
    registry: ?*c.struct_wl_registry,
    name: u32,
) callconv(.c) void {
    _ = .{ data, registry };
    log.debug("remove name: {d}", .{name});
}

const registry_listener: c.wl_registry_listener = .{
    .global = registry_handle_global,
    .global_remove = registry_handle_global_remove,
};

fn xdg_wm_base_handle_ping(
    _: ?*anyopaque,
    xdg_wm_base: ?*c.struct_xdg_wm_base,
    serial: u32,
) callconv(.c) void {
    c.xdg_wm_base_pong(xdg_wm_base, serial);
}

const xdg_wm_base_listener: c.xdg_wm_base_listener = .{
    .ping = xdg_wm_base_handle_ping,
};
