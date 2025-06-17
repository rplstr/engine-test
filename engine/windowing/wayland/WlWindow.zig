const std = @import("std");
const proto = @import("proto");
const c = @cImport({
    @cInclude("wayland.h");
    @cInclude("xdg-shell.h");
});

const util = @import("util.zig");

const log = std.log.scoped(.wayland);
const WEvent = proto.WEvent;
const WDescription = proto.WDescription;
const WlConn = @import("../wayland.zig").WlConn;

conn: *WlConn,

surface: *c.struct_wl_surface = undefined,
xdg_surface: *c.struct_xdg_surface = undefined,
xdg_toplevel: *c.struct_xdg_toplevel = undefined,

width: u16,
height: u16,

pub fn init(conn: *WlConn, description: WDescription) !*@This() {
    if (conn.closed) {
        log.err("cannot create window: connection is closed", .{});
        return error.Closed;
    }

    const wl_window_state = try conn.allocator.create(@This());
    errdefer conn.allocator.destroy(wl_window_state);
    wl_window_state.* = .{
        .conn = conn,
        .width = description.width,
        .height = description.height,
    };

    wl_window_state.surface = c.wl_compositor_create_surface(conn.compositor.?) orelse {
        log.err("failed to create wl_surface", .{});
        return error.FailedToCreateWlSurface;
    };
    errdefer c.wl_surface_destroy(wl_window_state.surface);

    wl_window_state.xdg_surface = c.xdg_wm_base_get_xdg_surface(
        conn.xdg_wm_base.?,
        wl_window_state.surface,
    ) orelse {
        log.err("xdg_surface is unavailable", .{});
        return error.MissingXdgSurface;
    };
    errdefer c.xdg_surface_destroy(wl_window_state.xdg_surface);

    wl_window_state.xdg_toplevel = c.xdg_surface_get_toplevel(wl_window_state.xdg_surface) orelse {
        log.err("unable to obtain xdg_toplevel for surface", .{});
        return error.MissingXdgToplevel;
    };
    errdefer c.xdg_toplevel_destroy(wl_window_state.xdg_toplevel);

    if (description.title) |title| {
        c.xdg_toplevel_set_title(wl_window_state.xdg_toplevel, title);
    }

    if (-1 == c.xdg_surface_add_listener(
        wl_window_state.xdg_surface,
        &xdg_surface_listener,
        wl_window_state,
    )) {
        log.err("failed to add xdg_surface listener", .{});
        return error.FailedToAddXdgSurfaceListener;
    }

    // c.wl_surface_attach(
    //     wl_window_state.surface,
    //     wl_window_state.front_buffer,
    //     0,
    //     0,
    // );
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

pub fn deinit(self: *@This()) void {
    c.xdg_toplevel_destroy(self.xdg_toplevel);
    c.xdg_surface_destroy(self.xdg_surface);
    c.wl_surface_destroy(self.surface);

    self.conn.allocator.destroy(self);
}

pub fn createBuffer(self: *@This()) !*c.struct_wl_buffer {

    // pixel format: `c.WL_SHM_FORMAT_XRGB8888`
    const width: i32 = self.width;
    const height: i32 = self.height;
    const stride: i32 = width * 4;
    const buffer_size: i32 = height * stride;

    // TODO: linux dmabuf instead once there is a renderer

    const shm_fd = try util.shmCreate(@intCast(buffer_size));
    errdefer std.posix.close(shm_fd);

    const shm_pool_data = try std.posix.mmap(
        null,
        @intCast(buffer_size),
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        shm_fd,
        0,
    );

    // fill both front and back buffers with white
    // @memset(@as([*]volatile u32, @ptrCast(shm_pool_data))[0..@intCast(width * height)], 0xFF8000);
    @memset(@as([]volatile u8, shm_pool_data), 0xFF);

    const shm_pool = c.wl_shm_create_pool(
        self.conn.shm.?,
        shm_fd,
        buffer_size,
    ) orelse {
        log.err("failed to create wl_shm_pool", .{});
        return error.FailedToCreateWlShmPool;
    };
    errdefer c.wl_shm_pool_destroy(shm_pool);

    const buffer = c.wl_shm_pool_create_buffer(
        shm_pool,
        0,
        width,
        height,
        stride,
        c.WL_SHM_FORMAT_XRGB8888,
    ) orelse {
        log.err("failed to create wl_buffer", .{});
        return error.FailedToCreateWlBuffer;
    };
    errdefer c.wl_buffer_destroy(buffer);

    _ = c.wl_buffer_add_listener(buffer, &buffer_listener, null);

    return buffer;
}

fn xdgSurfaceHandleConfigure(
    data: ?*anyopaque,
    xdg_surface: ?*c.struct_xdg_surface,
    serial: u32,
) callconv(.c) void {
    const self: *@This() = @alignCast(@ptrCast(data.?));

    c.xdg_surface_ack_configure(xdg_surface, serial);

    const buffer = self.createBuffer() catch |err| {
        log.err("failed to create a surface buffer: {}", .{err});
        return;
    };

    c.wl_surface_attach(
        self.surface,
        buffer,
        0,
        0,
    );
    c.wl_surface_commit(self.surface);
    log.info("committed", .{});
}

const xdg_surface_listener: c.xdg_surface_listener = .{
    .configure = xdgSurfaceHandleConfigure,
};

fn bufferHandleRelease(_: ?*anyopaque, buffer: ?*c.struct_wl_buffer) callconv(.c) void {
    if (buffer) |b| c.wl_buffer_destroy(b);
}

const buffer_listener: c.wl_buffer_listener = .{
    .release = bufferHandleRelease,
};
