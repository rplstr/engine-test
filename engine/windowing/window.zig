const builtin = @import("builtin");

/// Immutable compile-time description of a window.
pub const WDescription = extern struct {
    /// Client-area width in pixels.
    width: u16,
    /// Client-area height in pixels.
    height: u16,
    /// Optional UTF-8 NUL-terminated title of the window.
    title: ?[*:0]const u8,
};

/// Enumeration of every event we can currently emit.
pub const WEventKind = enum(u8) {
    none,
    close,
};

/// Description of a single event.
pub const WEvent = extern struct {
    /// What happened. (see `WEventKind`)
    kind: WEventKind,
    /// Extra numeric payload (keycode / button id / etc.).
    code: u32,
};

const Backend = switch (builtin.os.tag) {
    .windows => @import("win32.zig"),
    // TODO: wayland, cocoa
    else => @import("x11.zig"),
};

/// Creates and shows a native window.
pub export fn w_open_window(description: *const WDescription) callconv(.c) u64 {
    return Backend.openWindow(description.*);
}

/// Non-blocking. Returns `true` if an event for `handle` was placed in `out`.
pub export fn w_poll(out: *WEvent) callconv(.c) bool {
    return Backend.poll(out);
}

/// Destroys a window previously created by `w_open_window`.
pub export fn w_close_window(handle: u64) callconv(.c) void {
    Backend.closeWindow(handle);
}
