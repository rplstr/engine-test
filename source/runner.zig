const std = @import("std");
const log = std.log;
const builtin = @import("builtin");

/// Defines the type signature for a module's initialization function.
const init_fn = *const fn (allocator: *std.mem.Allocator) callconv(.C) void;
/// Defines the type signature for a module's de-initialization function.
const deinit_fn = *const fn () callconv(.C) void;

/// Represents a single, successfully loaded dynamic module at runtime.
pub const Module = struct {
    /// The handle to the opened dynamic library (.so, .dll, etc.).
    lib: std.DynLib,
    /// A cached function pointer to the module's `_deinit` function.
    deinit: deinit_fn,
    /// A heap-allocated copy of the module's name, used for identification and cleanup.
    name: []const u8,
};

comptime {
    if (builtin.os.tag == .wasi or builtin.os.tag == .freestanding) {
        @compileError("dynamic loading is unavailable for this target");
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var alloc = gpa.allocator();

    var loaded_modules = std.ArrayList(Module).init(alloc);
    defer unloadAll(&loaded_modules);

    const manifest_modules = try readModuleList(alloc);

    defer {
        for (manifest_modules) |m| alloc.free(m);
        alloc.free(manifest_modules);
    }

    if (manifest_modules.len == 0) {
        log.info("no modules to load", .{});
        return;
    }

    log.info("manifest has {d} valid modules to load", .{manifest_modules.len});

    for (manifest_modules) |mod_name| {
        if (hasLoaded(&loaded_modules, mod_name)) {
            log.warn("skipping duplicate module in manifest: {s}", .{mod_name});
            continue;
        }

        try loadModule(&alloc, &loaded_modules, mod_name);
    }
}

/// De-initializes and unloads all modules in the provided list.
pub fn unloadAll(mods: *std.ArrayList(Module)) void {
    if (mods.items.len == 0) return;

    log.info("unloading {d} total modules", .{mods.items.len});

    var i = mods.items.len;
    while (i > 0) {
        i -= 1;
        var m = &mods.items[i];

        log.info("* '{s}'", .{m.name});
        m.deinit();

        m.lib.close();
        mods.allocator.free(m.name);
    }
    log.info("done", .{});
    mods.deinit();
}

/// Dynamically loads a single module by name.
fn loadModule(alloc: *std.mem.Allocator, list: *std.ArrayList(Module), name: []const u8) !void {
    const path = try libPath(alloc.*, name);
    defer alloc.free(path);

    log.debug("opening library for module '{s}' from {s}", .{ name, path });
    var lib = try std.DynLib.open(path);

    errdefer lib.close();

    const init = try lookupSym(init_fn, &lib, alloc.*, "{s}_init", name);
    const deinit = try lookupSym(deinit_fn, &lib, alloc.*, "{s}_deinit", name);

    log.debug("initializing module '{s}'", .{name});
    init(alloc);

    const stored_name = try alloc.dupe(u8, name);

    errdefer alloc.free(stored_name);

    try list.append(.{
        .lib = lib,
        .deinit = deinit,
        .name = stored_name,
    });

    log.info("done", .{});
}

/// Checks if a module with the given name has already been loaded.
fn hasLoaded(list: *const std.ArrayList(Module), name: []const u8) bool {
    for (list.items) |m| {
        if (std.mem.eql(u8, m.name, name)) return true;
    }
    return false;
}

/// Reads and parses the `modules.json` manifest file from the current directory.
fn readModuleList(alloc: std.mem.Allocator) ![][]const u8 {
    const manifest_path = "modules.json";

    const file = std.fs.cwd().openFile(manifest_path, .{}) catch |e| switch (e) {
        error.FileNotFound => {
            log.warn("manifest '{s}' not found, no modules will be loaded", .{manifest_path});
            return alloc.alloc([]const u8, 0);
        },
        else => |err| {
            log.err("could not open manifest '{s}': {any}", .{ manifest_path, err });
            return err;
        },
    };
    defer file.close();

    const buf = try file.readToEndAlloc(alloc, 1 * 1024 * 1024);
    defer alloc.free(buf);

    const Manifest = struct { modules: []const []const u8 = &.{} };
    var parsed = try std.json.parseFromSlice(Manifest, alloc, buf, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const src_modules = parsed.value.modules;
    if (src_modules.len == 0) {
        log.info("manifest '{s}' is empty or contains no modules", .{manifest_path});
        return alloc.alloc([]const u8, 0);
    }

    var out_modules = try alloc.alloc([]const u8, src_modules.len);

    errdefer {
        for (out_modules) |m| alloc.free(m);
        alloc.free(out_modules);
    }

    for (src_modules, 0..) |m, i| {
        out_modules[i] = try alloc.dupe(u8, m);
    }

    return out_modules;
}

/// Composes the platform-specific shared library filename for a given module name.
///
/// For example, "engine" becomes "libengine.so" on Linux, "engine.dll" on
/// Windows, and "engine.dylib" on macOS.
fn sharedName(alloc: std.mem.Allocator, mod_name: []const u8) ![]u8 {
    const prefix = if (builtin.os.tag == .windows) "" else "lib";
    const suffix = switch (builtin.os.tag) {
        .windows => ".dll",
        .macos => ".dylib",
        else => ".so",
    };
    return std.fmt.allocPrint(alloc, "{s}{s}{s}", .{ prefix, mod_name, suffix });
}

/// Creates an absolute path to a module's shared library file.
fn libPath(alloc: std.mem.Allocator, mod_name: []const u8) ![]u8 {
    const dir = try std.fs.selfExeDirPathAlloc(alloc);
    defer alloc.free(dir);
    const name = try sharedName(alloc, mod_name);
    defer alloc.free(name);
    return std.fs.path.join(alloc, &.{ dir, name });
}

/// Looks up a symbol by name within a given dynamic library.
fn lookupSym(comptime T: type, lib: *std.DynLib, alloc: std.mem.Allocator, comptime fmt: []const u8, mod_name: []const u8) !T {
    const sym_name = try std.fmt.allocPrintZ(alloc, fmt, .{mod_name});
    defer alloc.free(sym_name);

    return lib.lookup(T, sym_name) orelse {
        log.err("missing required symbol '{s}' in module '{s}'", .{ sym_name, mod_name });
        return error.MissingSymbol;
    };
}
