//! wayland backend for the windowing sub-module.
const std = @import("std");
const wayland = @cImport({
    @cInclude("wayland.h");
});

const WEvent = @import("window.zig").WEvent;
const WDescription = @import("window.zig").WDescription;

/// Do not invoke directly; use `w_open_window` instead.
pub fn openWindow(description: WDescription) u64 {
    std.log.info("open window {}", .{description});
    return 0;
}

/// Do not invoke directly; use `w_poll` instead.
pub fn poll(out: *WEvent) bool {
    _ = out;
    return false;
}

/// Do not invoke directly; use `w_close_window` instead.
pub fn closeWindow(handle: u64) void {
    _ = handle;
}
