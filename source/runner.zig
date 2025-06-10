const std = @import("std");
const log = std.log;
const builtin = @import("builtin");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var alloc = gpa.allocator();

    var mods = std.ArrayList(Module).init(alloc);
    defer {
        unloadAll(&mods);
        mods.deinit();
    }

    const argv = try std.process.argsAlloc(alloc);

    defer std.process.argsFree(alloc, argv);
    const cli = if (argv.len > 1) argv[1] else "";

    const manifest = readModuleList(alloc) catch |e| {
        log.err("failed to read modules.json: {any}", .{e});
        return e;
    };
    log.info("manifest modules: {any}", .{manifest});

    try loadModule(&alloc, &mods, "engine");

    if (cli.len != 0) {
        if (!hasLoaded(&mods, cli)) {
            log.info("loading requested module: {s}", .{cli});
            try loadModule(&alloc, &mods, cli);
        }

        for (manifest) |m| alloc.free(m);
        alloc.free(manifest);
    } else {
        for (manifest) |m| {
            if (hasLoaded(&mods, m)) {
                alloc.free(m);
                continue;
            }
            log.info("loading manifest module: {s}", .{m});
            try loadModule(&alloc, &mods, m);
            log.info("module '{s}' loaded from manifest", .{m});
            alloc.free(m);
        }

        alloc.free(manifest);
    }
}

/// Symbol type for a module initializer function.
/// The runner passes its allocator to this function.
/// Must be exported as `<module>_init` from each dynamic library.
const init_fn = *const fn (*std.mem.Allocator) callconv(.C) void;

/// Symbol type for a module clean-up function.
/// Must be exported as `<module>_deinit` from each dynamic library.
const deinit_fn = *const fn () callconv(.C) void;

/// Runtime descriptor for a single loaded module.
/// Stores the dynamic library handle, clean-up symbol, and a copy of
/// its name so we can avoid duplicate loads and free memory reliably.
pub const Module = struct {
    lib: std.DynLib,
    deinit: deinit_fn,
    name: []const u8,
};

comptime {
    if (builtin.os.tag == .wasi or builtin.os.tag == .freestanding) {
        @compileError("dynamic loading is unavailable for this target");
    }
}

/// Compose the platform-specific file name of the shared library for `mod`.
/// Example on Linux: `libengine.so`, on Windows: `engine.dll`.
/// The returned slice is heap-allocated and must be freed by the caller.
fn sharedName(alloc: std.mem.Allocator, mod: []const u8) ![]u8 {
    const ext = switch (builtin.os.tag) {
        .windows => ".dll",
        .macos => ".dylib",
        else => ".so",
    };
    const pref = if (builtin.os.tag == .windows) "" else "lib";
    return std.fmt.allocPrint(alloc, "{s}{s}{s}", .{ pref, mod, ext });
}

/// Join the executable directory with the library file name to obtain
/// an absolute path to the module shared object.
fn libPath(alloc: std.mem.Allocator, mod: []const u8) ![]u8 {
    const dir = try std.fs.selfExeDirPathAlloc(alloc);
    defer alloc.free(dir);
    const name = try sharedName(alloc, mod);
    defer alloc.free(name);
    return std.fs.path.join(alloc, &.{ dir, name });
}

/// Allocate a zero-terminated string using `std.fmt.allocPrintZ`.
fn allocZ(alloc: std.mem.Allocator, comptime fmt: []const u8, mod: []const u8) ![:0]u8 {
    return std.fmt.allocPrintZ(alloc, fmt, .{mod});
}

/// Look up a symbol named using `fmt` inside `lib` and
/// return it as the requested type `T`.
fn lookupSym(comptime T: type, lib: *std.DynLib, alloc: std.mem.Allocator, comptime fmt: []const u8, mod: []const u8) !T {
    const sym = try allocZ(alloc, fmt, mod);
    defer alloc.free(sym);
    return lib.lookup(T, sym) orelse error.MissingSymbol;
}

/// Read `modules.json` from the working directory and return the list of
/// additional modules to load (excluding "engine"). When the
/// file is absent return an empty slice so fallback can be used.
fn readModuleList(alloc: std.mem.Allocator) ![]const []const u8 {
    const path = "modules.json";

    var file = std.fs.cwd().openFile(path, .{}) catch |e| switch (e) {
        error.FileNotFound => return alloc.alloc([]const u8, 0),
        else => return e,
    };
    defer file.close();

    const buf = try file.readToEndAlloc(alloc, 1 << 20);
    defer alloc.free(buf);

    const Parsed = struct { modules: []const []const u8 = &.{} };
    const parsed = try std.json.parseFromSlice(Parsed, alloc, buf, .{});
    defer parsed.deinit();

    const src = parsed.value.modules;
    var out = try alloc.alloc([]const u8, src.len);
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        out[i] = try alloc.dupe(u8, src[i]);
    }
    return out;
}

/// Helper that opens `path` as a dynamic library and logs an error
/// if the operation fails. The caller is responsible for closing the handle.
fn openDynLib(path: []const u8) !std.DynLib {
    log.debug("opening shared library from {s}", .{path});
    return std.DynLib.open(path) catch |e| {
        log.err("failed to open shared library '{s}': {any}", .{ path, e });
        return e;
    };
}

/// Dynamically load the module `name`, execute its initializer, and push an
/// entry to `list`. Any error closes the library.
fn loadModule(alloc: *std.mem.Allocator, list: *std.ArrayList(Module), name: []const u8) !void {
    log.debug("resolving library path for module '{s}'", .{name});
    var lib = blk: {
        const path = try libPath(alloc.*, name);
        defer alloc.free(path);
        break :blk try openDynLib(path);
    };
    log.info("library loaded for module '{s}'", .{name});

    const init = lookupSym(init_fn, &lib, alloc.*, "{s}_init", name) catch |e| {
        log.err("missing init symbol in module '{s}'", .{name});
        lib.close();
        return e;
    };
    log.debug("found init symbol for '{s}'", .{name});
    init(@constCast(alloc));
    log.info("module '{s}' initialized", .{name});

    const deinit = lookupSym(deinit_fn, &lib, alloc.*, "{s}_deinit", name) catch |e| {
        log.err("missing deinit symbol in module '{s}'", .{name});
        lib.close();
        return e;
    };
    log.debug("found deinit symbol for '{s}'", .{name});

    const stored_name = try alloc.*.dupe(u8, name);
    try list.append(.{ .lib = lib, .deinit = deinit, .name = stored_name });
    log.info("done", .{});
}

/// De-initialize and close all modules in reverse order of loading.
pub fn unloadAll(mods: *std.ArrayList(Module)) void {
    const alloc = mods.allocator;
    const total = mods.items.len;
    log.info("unloading {d} total modules", .{total});
    var i: usize = total;
    while (i > 0) {
        i -= 1;
        var m = mods.items[i];
        log.info("deinitialsing module '{s}'", .{m.name});
        m.deinit();
        log.info("closing library for module '{s}'", .{m.name});
        m.lib.close();
        alloc.free(m.name);
    }
    log.info("done", .{});
}

/// Check if a module with the given name has been loaded.
fn hasLoaded(list: *const std.ArrayList(Module), name: []const u8) bool {
    for (list.items) |m| if (std.mem.eql(u8, m.name, name)) return true;
    return false;
}
