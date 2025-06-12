//! Windows backend for the windowing sub-module.

const w32 = @cImport(@cInclude("windows.h"));

const WDescription = @import("window.zig").WDescription;
const WEvent = @import("window.zig").WEvent;

const wnd_class: [*:0]const u8 = @ptrCast("wnd");
const def_title: [*:0]const u8 = @ptrCast("zig");

export fn wndProc(handle: w32.HWND, msg: w32.UINT, wparam: w32.WPARAM, lparam: w32.LPARAM) callconv(.c) w32.LRESULT {
    if (msg == w32.WM_DESTROY) {
        w32.PostQuitMessage(0);
        return 0;
    }
    return w32.DefWindowProcA(handle, msg, wparam, lparam);
}

fn registerClass(instance: w32.HINSTANCE) void {
    var dummy: w32.WNDCLASSA = undefined;
    if (w32.GetClassInfoA(instance, wnd_class, &dummy) != 0) return;

    var wc: w32.WNDCLASSA = .{
        .style = 0,
        .lpfnWndProc = wndProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = instance,
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = wnd_class,
    };
    _ = w32.RegisterClassA(&wc);
}

/// Do not invoke directly; use `w_open_window` instead.
pub fn openWindow(description: WDescription) u64 {
    const inst = w32.GetModuleHandleA(null);
    registerClass(inst);

    const title = if (description.title) |t| t else def_title;

    const hwnd = w32.CreateWindowExA(
        0,
        wnd_class,
        @ptrCast(title),
        w32.WS_OVERLAPPEDWINDOW,
        w32.CW_USEDEFAULT,
        w32.CW_USEDEFAULT,
        description.width,
        description.height,
        null,
        null,
        inst,
        null,
    );
    if (hwnd == null) return 0;

    _ = w32.ShowWindow(hwnd, w32.SW_SHOW);
    return @intFromPtr(hwnd);
}

/// Do not invoke directly; use `w_poll` instead.
pub fn poll(out: *WEvent) bool {
    var msg: w32.MSG = undefined;

    if (w32.PeekMessageA(&msg, null, 0, 0, w32.PM_REMOVE) == 0) {
        return false;
    }

    switch (msg.message) {
        w32.WM_CLOSE, w32.WM_QUIT => {
            out.* = .{ .kind = .close, .code = 0 };
            return true;
        },
        else => {
            _ = w32.TranslateMessage(&msg);
            _ = w32.DispatchMessageA(&msg);
            return false;
        },
    }
}

/// Do not invoke directly; use `w_close_window` instead.
pub fn closeWindow(handle: u64) void {
    if (handle == 0) return;
    _ = w32.DestroyWindow(@ptrFromInt(handle));
}
