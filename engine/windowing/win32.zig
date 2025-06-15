//! Windows backend for the windowing sub-module.
const builtin = @import("builtin");

const windows = @cImport(@cInclude("windows.h"));

const WDescription = @import("window.zig").WDescription;
const WEvent = @import("window.zig").WEvent;

const wnd_class: [*:0]const u8 = "wnd";
const def_title: [*:0]const u8 = "zig";

export fn wndProc(handle: windows.HWND, msg: windows.UINT, wparam: windows.WPARAM, lparam: windows.LPARAM) callconv(.c) windows.LRESULT {
    if (msg == windows.WM_DESTROY) {
        windows.PostQuitMessage(0);
        return 0;
    }
    return windows.DefWindowProcA(handle, msg, wparam, lparam);
}

fn registerClass(instance: windows.HINSTANCE) void {
    var dummy: windows.WNDCLASSA = undefined;
    if (windows.GetClassInfoA(instance, wnd_class, &dummy) != 0) return;

    var wc: windows.WNDCLASSA = .{
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
    _ = windows.RegisterClassA(&wc);
}

/// Do not invoke directly; use `w_open_window` instead.
pub fn openWindow(_: void, description: WDescription) u64 {
    const inst = windows.GetModuleHandleA(null);
    registerClass(inst);

    const title = if (description.title) |t| t else def_title;

    const hwnd = windows.CreateWindowExA(
        0,
        wnd_class,
        @ptrCast(title),
        windows.WS_OVERLAPPEDWINDOW,
        windows.CW_USEDEFAULT,
        windows.CW_USEDEFAULT,
        description.width,
        description.height,
        null,
        null,
        inst,
        null,
    );
    if (hwnd == null) return 0;

    _ = windows.ShowWindow(hwnd, windows.SW_SHOW);
    return @intFromPtr(hwnd);
}

/// Do not invoke directly; use `w_poll` instead.
pub fn poll(_: void, out: *WEvent) bool {
    var msg: windows.MSG = undefined;

    if (windows.PeekMessageA(&msg, null, 0, 0, windows.PM_REMOVE) == 0) {
        return false;
    }

    switch (msg.message) {
        windows.WM_CLOSE, windows.WM_QUIT => {
            out.* = .{ .kind = .close, .code = 0 };
            return true;
        },
        else => {
            _ = windows.TranslateMessage(&msg);
            _ = windows.DispatchMessageA(&msg);
            return false;
        },
    }
}

/// Do not invoke directly; use `w_close_window` instead.
pub fn closeWindow(_: void, handle: u64) void {
    if (handle == 0) return;
    _ = windows.DestroyWindow(@ptrFromInt(handle));
}
