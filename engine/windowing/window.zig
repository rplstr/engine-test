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
pub const WEventKind = enum(u8) { none, close };

/// Description of a single event.
pub const WEvent = extern struct {
    /// What happened. (see `WEventKind`)
    kind: WEventKind,
    /// Extra numeric payload.
    code: u32,
};

const Backend = switch (builtin.os.tag) {
    .windows => @import("win32.zig"),
    // TODO: wayland
    else => @import("x11.zig"),
};

/// Creates and shows a native window.
pub export fn w_open_window(description: *const WDescription) callconv(.C) u64 {
    return Backend.openWindow(description.*);
}

/// Non-blocking. Returns `true` if an event for `handle` was placed in `out`.
pub export fn w_poll(handle: u64, out: *WEvent) callconv(.C) bool {
    return Backend.poll(handle, out);
}

/// Destroys a window previously created by `w_open_window`.
pub export fn w_close_window(handle: u64) callconv(.C) void {
    Backend.closeWindow(handle);
}
