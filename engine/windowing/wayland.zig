//! wayland backend for the windowing sub-module.
const std = @import("std");
const wayland = @cImport({
    @cInclude("wayland.h");
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

    log.info("open window {}", .{description});
    return 0;
}

/// Do not invoke directly; use `w_poll` instead.
pub fn poll(out: *WEvent) bool {
    mode_once.call();
    if (mode.load(.monotonic) == .fallback) {
        return x11.poll(out);
    }

    return false;
}

/// Do not invoke directly; use `w_close_window` instead.
pub fn closeWindow(handle: u64) void {
    mode_once.call();
    if (mode.load(.monotonic) == .fallback) {
        return x11.closeWindow(handle);
    }
}

var mode_once = std.once(init);
var mode = std.atomic.Value(Mode).init(.fallback);

const Mode = enum(u8) {
    fallback,
    wayland,
};

/// lazily initializes wayland, and falls back to using x11 if it fails
fn init() void {
    tryInitWayland() catch |err| {
        log.info("Could not load wayland, falling back to X11: {}", .{err});
        return;
    };

    mode.store(.wayland, .monotonic); // ordered by std.once
    return;
}

fn tryInitWayland() !void {
    return error.Unimplemented;
}
