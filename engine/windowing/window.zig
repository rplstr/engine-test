const std = @import("std");
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

const backends = switch (builtin.os.tag) {
    .windows => struct {
        const win32 = @import("win32.zig");
    },
    else => struct {
        const x11 = @import("x11.zig");
        const wayland = @import("wayland.zig");
    },
};

const Backend = switch (builtin.os.tag) {
    .windows => union(enum) {
        uninitialized: void,
        win32: void,
    },
    else => union(enum) {
        uninitialized: void,
        x11: void,
        wayland: *backends.wayland.WlConn,
    },
};

var backend: Backend = .{ .uninitialized = {} };

pub fn init(allocator: std.mem.Allocator) void {
    // std.debug.dumpCurrentStackTrace(null);
    // defer _ = @atomicLoad(u8, @as(*u8, @ptrCast(&backend)), .seq_cst);
    defer std.log.debug("picked windowing backend: {s}", .{
        @tagName(backend),
    });

    switch (builtin.os.tag) {
        .windows => {
            backend = .{ .win32 = {} };
        },
        else => {
            if (backends.wayland.WlConn.init(allocator)) |wl_conn| {
                backend = .{ .wayland = wl_conn };
                return;
            } else |err| {
                std.log.debug("wayland connection failed: {}, using fallback windowing system", .{err});
            }

            backend = .{ .x11 = {} };
        },
    }
}

pub fn backendCall(comptime T: type, comptime function_name: []const u8, args: anytype) T {
    // std.debug.dumpCurrentStackTrace(null);
    // _ = @atomicLoad(u8, @as(*u8, @ptrCast(&backend)), .seq_cst);
    switch (std.meta.activeTag(backend)) {
        inline else => |tag| {
            // std.log.debug("windowing backend: {s}", .{@tagName(tag)});

            if (tag == .uninitialized) unreachable;

            const active_backend = @field(backends, @tagName(tag));
            const state = @field(backend, @tagName(tag));
            const func = @field(active_backend, function_name);

            // std.log.debug("calling {any} with {any}", .{
            //     &func,
            //     .{state} ++ args,
            // });

            return @call(.auto, func, .{state} ++ args);
        },
    }
}

// FIXME: remove this and use engine_init to call init
// instead once the dll dispatching problem is solved
fn lazyInit() void {
    init(std.heap.c_allocator);
}
var lazyInitOnce = std.once(lazyInit);

/// Creates and shows a native window.
pub export fn w_open_window(description: *const WDescription) callconv(.c) u64 {
    lazyInitOnce.call();
    return backendCall(u64, "openWindow", .{description.*});
}

/// Non-blocking. Returns `true` if an event for `handle` was placed in `out`.
pub export fn w_poll(out: *WEvent) callconv(.c) bool {
    lazyInitOnce.call();
    return backendCall(bool, "poll", .{out});
}

/// Destroys a window previously created by `w_open_window`.
pub export fn w_close_window(handle: u64) callconv(.c) void {
    lazyInitOnce.call();
    return backendCall(void, "closeWindow", .{handle});
}
