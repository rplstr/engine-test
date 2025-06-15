//! wayland backend for the windowing sub-module.
const std = @import("std");
const c = @cImport({
    @cInclude("wayland.h");
    @cInclude("xdg-shell.h");
});
const x11 = @import("x11.zig");

const log = std.log.scoped(.wayland);
const WEvent = @import("window.zig").WEvent;
const WDescription = @import("window.zig").WDescription;

/// Do not invoke directly; use `w_open_window` instead.
pub fn openWindow(description: WDescription) u64 {
    mode_once.call();
    if (mode.load(.monotonic) == .fallback) {
        return x11.openWindow(description);
    }

    const window = createWlWindow(description) catch |err| {
        log.err("failed to create wayland window: {}", .{err});
        return 0;
    };

    return @intFromPtr(window);
}

/// Do not invoke directly; use `w_poll` instead.
pub fn poll(out: *WEvent) bool {
    mode_once.call();
    if (mode.load(.monotonic) == .fallback) {
        return x11.poll(out);
    }

    const wl_state: *WlState = &wl_global_state;
    if (wl_state.closed) return false;

    while (c.wl_display_dispatch(wl_state.display) != -1) {}

    // TODO: poll instead:

    const display_fd = c.wl_display_get_fd(wl_state.display);
    var fds = [_]std.posix.pollfd{
        .{ .fd = display_fd, .events = std.posix.POLL.IN, .revents = 0 },
    };
    _ = std.posix.poll(fds[0..], 0) catch |err| {
        log.err("failed to poll display: {}", .{err});
        return false;
    };

    if (fds[0].revents == 0) return false;

    if (c.wl_display_dispatch(wl_state.display) == -1) {
        log.err("wayland connection closed unexpectedly", .{});
        wl_state.closed = true;
        return false;
    }

    // TODO: events

    return false;
}

/// Do not invoke directly; use `w_close_window` instead.
pub fn closeWindow(handle: u64) void {
    mode_once.call();
    if (mode.load(.monotonic) == .fallback) {
        return x11.closeWindow(handle);
    }

    // TODO:
}

//

fn createWlWindow(description: WDescription) !*WlWindowState {
    const wl_state: *WlState = &wl_global_state;
    if (wl_state.closed) return error.Closed;

    const wl_window_state = try std.heap.c_allocator.create(WlWindowState);
    errdefer std.heap.c_allocator.destroy(wl_window_state);
    wl_window_state.* = .{};

    wl_window_state.surface = c.wl_compositor_create_surface(wl_state.compositor.?) orelse {
        return error.FailedToCreateWlSurface;
    };
    errdefer c.wl_surface_destroy(wl_window_state.surface);

    wl_window_state.xdg_surface = c.xdg_wm_base_get_xdg_surface(
        wl_state.xdg_wm_base.?,
        wl_window_state.surface,
    ) orelse {
        return error.MissingXdgSurface;
    };
    errdefer c.xdg_surface_destroy(wl_window_state.xdg_surface);

    wl_window_state.xdg_toplevel = c.xdg_surface_get_toplevel(wl_window_state.xdg_surface) orelse {
        return error.MissingXdgToplevel;
    };
    errdefer c.xdg_toplevel_destroy(wl_window_state.xdg_toplevel);

    if (description.title) |title| {
        c.xdg_toplevel_set_title(wl_window_state.xdg_toplevel, title);
    }

    // pixel format: `c.WL_SHM_FORMAT_XRGB8888`
    // double buffering
    const width: i32 = description.width;
    const height: i32 = description.height;
    const stride: i32 = width * 4;
    const buffer_size: i32 = height * stride;
    const shm_pool_size: i32 = buffer_size * 2;

    // TODO: linux dmabuf instead once there is a renderer

    const shm_fd = try shm_create(@intCast(shm_pool_size));
    errdefer std.posix.close(shm_fd);

    const shm_pool_data = try std.posix.mmap(
        null,
        @intCast(shm_pool_size),
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        shm_fd,
        0,
    );

    const shm_pool = c.wl_shm_create_pool(
        wl_state.shm.?,
        shm_fd,
        shm_pool_size,
    ) orelse {
        return error.FailedToCreateWlShmPool;
    };
    errdefer c.wl_shm_pool_destroy(shm_pool);

    wl_window_state.front_buffer = c.wl_shm_pool_create_buffer(
        shm_pool,
        0,
        width,
        height,
        stride,
        c.WL_SHM_FORMAT_XRGB8888,
    ) orelse {
        return error.FailedToCreateWlBuffer;
    };
    errdefer c.wl_buffer_destroy(wl_window_state.front_buffer);

    wl_window_state.back_buffer = c.wl_shm_pool_create_buffer(
        shm_pool,
        buffer_size,
        width,
        height,
        stride,
        c.WL_SHM_FORMAT_XRGB8888,
    ) orelse {
        return error.FailedToCreateWlBuffer;
    };
    errdefer c.wl_buffer_destroy(wl_window_state.back_buffer);

    // fill both front and back buffers with white
    // @memset(@as([*]volatile u32, @ptrCast(shm_pool_data))[0..@intCast(width * height)], 0xFF8000);
    @memset(@as([]volatile u8, shm_pool_data), 0xFF);

    if (-1 == c.xdg_surface_add_listener(
        wl_window_state.xdg_surface,
        &xdg_surface_listener,
        wl_window_state,
    )) {
        return error.FailedToAddXdgSurfaceListener;
    }

    c.wl_surface_attach(
        wl_window_state.surface,
        wl_window_state.front_buffer,
        0,
        0,
    );
    c.wl_surface_damage(
        wl_window_state.surface,
        0,
        0,
        @bitCast(@as(u32, std.math.maxInt(u32))),
        @bitCast(@as(u32, std.math.maxInt(u32))),
    );
    c.wl_surface_commit(wl_window_state.surface);

    log.info("committed", .{});

    return wl_window_state;
}

//

var mode_once = std.once(init);
var mode = std.atomic.Value(Mode).init(.fallback);

const Mode = enum(u8) {
    fallback,
    wayland,
};

/// lazily initializes wayland, and falls back to using x11 if it fails
fn init() void {
    log.info("pid={}", .{std.os.linux.getpid()});
    tryInitWayland() catch |err| {
        log.info("Could not load wayland, falling back to X11: {}", .{err});
        return;
    };
    log.info("wl initialized", .{});

    mode.store(.wayland, .monotonic); // ordered by std.once
    return;
}

/// global wayland state
const WlState = struct {
    display: *c.struct_wl_display = undefined,
    registry: *c.struct_wl_registry = undefined,

    closed: bool = false,

    compositor: ?*c.struct_wl_compositor = null,
    shm: ?*c.struct_wl_shm = null,
    xdg_wm_base: ?*c.struct_xdg_wm_base = null,

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
};

const WlWindowState = struct {
    surface: *c.struct_wl_surface = undefined,
    xdg_surface: *c.struct_xdg_surface = undefined,
    xdg_toplevel: *c.struct_xdg_toplevel = undefined,

    front_buffer: ?*c.struct_wl_buffer = null,
    back_buffer: ?*c.struct_wl_buffer = null,
};

var wl_global_state: WlState = .{};

fn registry_handle_global(
    data: ?*anyopaque,
    registry: ?*c.struct_wl_registry,
    name: u32,
    interface: [*c]const u8,
    version: u32,
) callconv(.c) void {
    const wl_state: *WlState = @alignCast(@ptrCast(data.?));
    std.debug.assert(wl_state.registry == registry);

    log.debug("interface: {s}, version: {}, name: {d}", .{ interface, version, name });

    wl_state.tryBindInterface(
        "compositor",
        interface,
        name,
        &c.wl_compositor_interface,
        4,
    );

    wl_state.tryBindInterface(
        "shm",
        interface,
        name,
        &c.wl_shm_interface,
        1,
    );

    wl_state.tryBindInterface(
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

fn xdg_surface_handle_configure(
    data: ?*anyopaque,
    xdg_surface: ?*c.struct_xdg_surface,
    serial: u32,
) callconv(.c) void {
    const wl_window_state: *WlWindowState = @alignCast(@ptrCast(data.?));

    c.xdg_surface_ack_configure(xdg_surface, serial);

    if (wl_window_state.front_buffer) |front| {
        c.wl_surface_attach(
            wl_window_state.surface,
            front,
            0,
            0,
        );
        c.wl_surface_commit(wl_window_state.surface);
        log.info("committed", .{});
    }
}

const xdg_surface_listener: c.xdg_surface_listener = .{
    .configure = xdg_surface_handle_configure,
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

fn tryInitWayland() !void {
    wl_global_state.display = c.wl_display_connect(null) orelse {
        log.debug("failed to connect to Wayland display", .{});
        return error.FailedToConnect;
    };
    errdefer c.wl_display_disconnect(wl_global_state.display);

    wl_global_state.registry = c.wl_display_get_registry(wl_global_state.display) orelse {
        log.debug("failed to obtain wl_registry", .{});
        return error.FailedToConnect;
    };
    errdefer c.wl_registry_destroy(wl_global_state.registry);

    _ = c.wl_registry_add_listener(
        wl_global_state.registry,
        &registry_listener,
        &wl_global_state,
    );

    _ = c.wl_display_roundtrip(wl_global_state.display);

    _ = wl_global_state.compositor orelse {
        log.debug("failed to obtain wl_compositor", .{});
        return error.FailedToConnect;
    };

    _ = wl_global_state.shm orelse {
        log.debug("failed to obtain wl_shm", .{});
        return error.FailedToConnect;
    };

    _ = wl_global_state.xdg_wm_base orelse {
        log.debug("failed to obtain xdg_wm_base", .{});
        return error.FailedToConnect;
    };

    _ = c.xdg_wm_base_add_listener(
        wl_global_state.xdg_wm_base.?,
        &xdg_wm_base_listener,
        &wl_global_state,
    );

    _ = c.wl_display_roundtrip(wl_global_state.display);
}

fn shm_create(size: usize) !std.posix.fd_t {
    for (0..100) |_| {
        // 100 attempts

        const name = randomShmName();

        const fd = std.c.shm_open(@ptrCast(&name), @bitCast(std.posix.O{
            .ACCMODE = .RDWR,
            .CREAT = true,
            .EXCL = true,
        }), 0o666);

        switch (std.posix.errno(fd)) {
            .SUCCESS => {},
            .EXIST => continue,
            else => |other| {
                log.err("failed to open shm: {}", .{other});
                return std.posix.unexpectedErrno(other);
            },
        }

        errdefer std.posix.close(fd);

        const ret = std.c.shm_unlink(@ptrCast(&name));
        switch (std.posix.errno(ret)) {
            .SUCCESS => {},
            else => |other| {
                log.err("failed to unlink shm: {}", .{other});
                return std.posix.unexpectedErrno(other);
            },
        }

        try std.posix.ftruncate(fd, size);

        return fd;
    }

    return error.FailedToCreateShm;
}

fn randomShmName() [32]u8 {
    var buf = [_]u8{0} ** 32;
    var writer = std.io.fixedBufferStream(buf[0..]);

    std.fmt.format(writer.writer(), "/wl-shm-{x:0>16}", .{
        std.crypto.random.int(u64),
    }) catch unreachable;

    std.debug.assert(buf[31] == 0);
    return buf;
}
