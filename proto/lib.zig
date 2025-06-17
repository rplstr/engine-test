const std = @import("std");
const log = std.log.scoped(.proto);

// runner interface

pub const PfnInstallPfn = *const fn (func: [*c]const u8, pfn: *const anyopaque) callconv(.c) bool;
pub const PfnFindPfn = *const fn (func: [*c]const u8) callconv(.c) ?*const anyopaque;

pub var installPfn: PfnInstallPfn = undefined;
pub var findPfn: PfnFindPfn = undefined;

pub fn loadRunner(entry: PfnFindPfn) !void {
    findPfn = entry;
    load("installPfn") orelse {
        log.err("failed to load required symbol 'installPfn' from runner", .{});
        return error.FailedToLoadInstallPfn;
    };
}

pub fn installRunner() void {
    install("installPfn");
    install("findPfn");
}

// engine interface

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

pub const PfnWOpenWindow = *const fn (description: *const WDescription) callconv(.c) u64;
pub const PfnWPoll = *const fn (out: *WEvent) callconv(.c) bool;
pub const PfnWCloseWindow = *const fn (handle: u64) callconv(.c) void;

pub var w_open_window: PfnWOpenWindow = undefined;
pub var w_poll: PfnWPoll = undefined;
pub var w_close_window: PfnWCloseWindow = undefined;

pub fn loadEngine() !void {
    load("w_open_window") orelse {
        log.err("failed to load 'w_open_window' from engine", .{});
        return error.FailedToLoadWOpenWindow;
    };
    load("w_poll") orelse {
        log.err("failed to load 'w_poll' from engine", .{});
        return error.FailedToLoadWPoll;
    };
    load("w_close_window") orelse {
        log.err("failed to load 'w_close_window' from engine", .{});
        return error.FailedToLoadWCloseWindow;
    };
}

pub fn installEngine() void {
    install("w_open_window");
    install("w_poll");
    install("w_close_window");
}

// utils for proto

fn load(comptime func: [*c]const u8) ?void {
    @field(@This(), std.mem.span(func)) = @ptrCast(findPfn(func) orelse return null);
}

fn install(comptime func: [*c]const u8) void {
    _ = installPfn(func, @field(@This(), std.mem.span(func)));
}
