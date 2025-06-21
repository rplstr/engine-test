const std = @import("std");
const builtin = @import("builtin");
const interface = @import("interface.zig");

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

fn backendCall(comptime T: type, comptime function_name: []const u8, args: anytype) T {
    switch (std.meta.activeTag(backend)) {
        inline else => |tag| {
            if (tag == .uninitialized) unreachable;

            const active_backend = @field(backends, @tagName(tag));
            const state = @field(backend, @tagName(tag));
            const func = @field(active_backend, function_name);

            return @call(.auto, func, .{state} ++ args);
        },
    }
}

fn init(allocator: *std.mem.Allocator) callconv(.c) void {
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

fn open_window(description: *const interface.Description) callconv(.c) u64 {
    return backendCall(u64, "openWindow", .{description.*});
}

fn poll(out: *interface.Event) callconv(.c) bool {
    return backendCall(bool, "poll", .{out});
}

fn close_window(handle: u64) callconv(.c) void {
    return backendCall(void, "closeWindow", .{handle});
}

pub export const windowing_vtable: interface.VTable = .{
    .init = init,
    .open_window = open_window,
    .poll = poll,
    .close_window = close_window,
};
