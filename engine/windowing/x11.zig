//! X11 backend for the windowing sub-module.
const x11 = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xutil.h");
});
const WEvent = @import("window.zig").WEvent;
const WDescription = @import("window.zig").WDescription;

/// Do not invoke directly; use `w_open_window` instead.
pub fn openWindow(description: WDescription) u64 {
    const display = x11.XOpenDisplay(null) orelse return 0;
    const screen = x11.XDefaultScreen(display);

    const win = x11.XCreateSimpleWindow(
        display,
        x11.XRootWindow(display, screen),
        0,
        0,
        description.width,
        description.height,
        1,
        x11.XBlackPixel(display, screen),
        x11.XWhitePixel(display, screen),
    );

    if (description.title) |t| _ = x11.XStoreName(display, win, @ptrCast(t));

    _ = x11.XMapWindow(display, win);
    _ = x11.XFlush(display);
    _ = x11.XCloseDisplay(display);
    return win;
}

/// Do not invoke directly; use `w_poll` instead.
pub fn poll(out: *WEvent) bool {
    const display = x11.XOpenDisplay(null) orelse return false;

    if (x11.XPending(display) == 0) {
        _ = x11.XCloseDisplay(display);
        return false;
    }

    var xevent: x11.XEvent = undefined;
    _ = x11.XNextEvent(display, &xevent);

    var got = false;
    switch (xevent.type) {
        x11.DestroyNotify => {
            out.* = .{ .kind = .close, .code = 0 };
            got = true;
        },
        else => {},
    }

    _ = x11.XCloseDisplay(display);
    return got;
}

/// Do not invoke directly; use `w_close_window` instead.
pub fn closeWindow(handle: u64) void {
    if (handle == 0) return;
    const display = x11.XOpenDisplay(null) orelse return;
    x11.XDestroyWindow(display, @intCast(handle));
    _ = x11.XCloseDisplay(display);
}
