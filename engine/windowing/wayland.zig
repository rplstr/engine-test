//! wayland backend for the windowing sub-module.
const std = @import("std");
const proto = @import("proto");
const c = @cImport({
    @cInclude("wayland.h");
    @cInclude("xdg-shell.h");
});
const x11 = @import("x11.zig");

const log = std.log.scoped(.wayland);
const WEvent = proto.WEvent;
const WDescription = proto.WDescription;
pub const WlConn = @import("wayland/WlConn.zig");
pub const WlWindow = @import("wayland/WlWindow.zig");

/// Do not invoke directly; use `w_open_window` instead.
pub fn openWindow(wl_conn: *WlConn, description: WDescription) u64 {
    const window = WlWindow.init(wl_conn, description) catch |err| {
        log.err("failed to create wayland window: {}", .{err});
        return 0;
    };

    return @intFromPtr(window);
}

/// Do not invoke directly; use `w_poll` instead.
pub fn poll(wl_conn: *WlConn, out: *WEvent) bool {
    _ = out;

    while (c.wl_display_dispatch(wl_conn.display) != -1) {}

    // TODO: poll instead:

    const display_fd = c.wl_display_get_fd(wl_conn.display);
    var fds = [_]std.posix.pollfd{
        .{ .fd = display_fd, .events = std.posix.POLL.IN, .revents = 0 },
    };
    _ = std.posix.poll(fds[0..], 0) catch |err| {
        log.err("failed to poll display: {}", .{err});
        return false;
    };

    if (fds[0].revents == 0) return false;

    if (c.wl_display_dispatch(wl_conn.display) == -1) {
        log.err("wayland connection closed unexpectedly", .{});
        wl_conn.closed = true;
        return false;
    }

    // TODO: events

    return false;
}

/// Do not invoke directly; use `w_close_window` instead.
pub fn closeWindow(wl_conn: *WlConn, handle: u64) void {
    _ = .{ wl_conn, handle };

    // TODO:
}
