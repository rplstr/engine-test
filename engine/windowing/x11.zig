//! X11 backend for the windowing sub-module.
const x11 = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xutil.h");
});
const WEvent = @import("window.zig").WEvent;
const WDescription = @import("window.zig").WDescription;

var display: ?*x11.Display = null;
var wm_delete: x11.Atom = 0;

/// Do not invoke directly; use `w_open_window` instead.
pub fn openWindow(_: void, description: WDescription) u64 {
    if (display == null) {
        display = x11.XOpenDisplay(null) orelse return 0;
    }
    const d = display.?;
    const screen = x11.XDefaultScreen(d);

    const win = x11.XCreateSimpleWindow(
        d,
        x11.XRootWindow(d, screen),
        0,
        0,
        description.width,
        description.height,
        1,
        x11.XBlackPixel(d, screen),
        x11.XWhitePixel(d, screen),
    );

    if (description.title) |t| _ = x11.XStoreName(d, win, @ptrCast(t));

    // Register for WM_DELETE_WINDOW so we get a ClientMessage instead of the
    // window manager killing us immediately.
    if (wm_delete == 0) {
        wm_delete = x11.XInternAtom(d, "WM_DELETE_WINDOW", 0);
    }
    _ = x11.XSetWMProtocols(d, win, &wm_delete, 1);

    _ = x11.XMapWindow(d, win);
    _ = x11.XFlush(d);
    return win;
}

/// Do not invoke directly; use `w_poll` instead.
pub fn poll(_: void, out: *WEvent) bool {
    const d = display orelse return false;

    if (x11.XPending(d) == 0) {
        return false;
    }

    var xevent: x11.XEvent = undefined;
    _ = x11.XNextEvent(d, &xevent);

    var got = false;
    switch (xevent.type) {
        x11.ClientMessage => {
            if (@as(c_long, @intCast(wm_delete)) == xevent.xclient.data.l[0]) {
                out.* = .{ .kind = .close, .code = 0 };
                got = true;
            }
        },
        else => {},
    }

    return got;
}

/// Do not invoke directly; use `w_close_window` instead.
pub fn closeWindow(_: void, handle: u64) void {
    if (handle == 0 or display == null) return;
    const d = display.?;
    _ = x11.XDestroyWindow(d, @intCast(handle));
    _ = x11.XFlush(d);
}
