const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const modules = discoverModules(b.allocator) catch |e| std.debug.panic("module discovery failed: {}", .{e});

    validateSymbols(b.allocator, modules) catch |e| std.debug.panic("failed to validate symbols: {}", .{e});

    const exe = b.addExecutable(.{
        .name = "runner",
        .root_source_file = b.path("source/runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    b.installArtifact(exe);

    var map = std.StringHashMap(*std.Build.Step.Compile).init(b.allocator);
    map.ensureTotalCapacity(modules.len) catch unreachable;

    // Compile libraries.
    const expected_abi: u32 = 1;
    for (modules) |m| {
        var src: []u8 = undefined;

        if (m.root_source_file.len != 0) {
            src = std.fs.path.join(b.allocator, &.{ m.name, m.root_source_file }) catch unreachable;
        } else {
            src = std.fmt.allocPrint(b.allocator, "{s}/{s}.zig", .{ m.name, m.name }) catch unreachable;
        }

        checkExports(b.allocator, src, m) catch |e| std.debug.panic("symbol validation failed: {}", .{e});

        const mod = b.addModule(m.name, .{
            .root_source_file = b.path(src),
            .target = target,
            .optimize = optimize,
        });

        if (m.abi != expected_abi) {
            std.debug.panic("ABI mismatch for module '{s}', found {} expected {}", .{ m.name, m.abi, expected_abi });
        }

        const lib = b.addLibrary(.{
            .name = m.name,
            .root_module = mod,
            .linkage = .dynamic,
            .version = m.version,
        });

        lib.linkLibC();
        b.installArtifact(lib);
        map.putAssumeCapacity(m.name, lib);
    }

    // Resolve links.
    for (modules) |m| {
        const lib = map.get(m.name).?;
        for (m.deps) |d| {
            const dep_lib = map.get(d) orelse std.debug.panic("unknown dependency '{s}' for '{s}'", .{ d, m.name });
            lib.linkLibrary(dep_lib);
            lib.root_module.addImport(d, dep_lib.root_module);
        }
    }

    b.default_step.dependOn(&exe.step);
}

/// Module descriptor parsed from `manifest.json` found in each module directory.
///
/// ```json
/// manifest.json
/// {
///   "name": "engine",
///   "version": {"major":1,"minor":0,"patch":0},
///   "abi": 1,
///   "root_source_file": "custom.zig",
///   "symbols": ["init", "tick", "shutdown"],
///   "deps": ["core"]
/// }
/// ```
///
/// * `name`     – folder name & library name.
/// * `root_source_file` – entry .zig file relative to the module directory (defaults to `<name>.zig`).
/// * `version`          – semantic version used for `.so/.dll` version info.
/// * `abi`              – numeric ABI revision checked at runtime.
/// * `deps`             – other module names this module links against.
/// * `symbols`          – exported function names (e.g. init, tick, shutdown).
const ManifestModule = struct {
    name: []const u8,
    root_source_file: []const u8 = "",
    version: std.SemanticVersion = .{ .major = 1, .minor = 0, .patch = 0 },
    abi: u32 = 1,
    deps: []const []const u8 = &.{},
    symbols: []const []const u8 = &.{},
};

/// Read and parse `dir_name/manifest.json`.
/// Returns a fully validated `ManifestModule` instance.
fn readManifest(alloc: std.mem.Allocator, dir_name: []const u8) !ManifestModule {
    const path = try std.fs.path.join(alloc, &.{ dir_name, "manifest.json" });
    defer alloc.free(path);
    const buf = try std.fs.cwd().readFileAlloc(alloc, path, 1 << 18);
    const parsed = try std.json.parseFromSlice(ManifestModule, alloc, buf, .{});
    return parsed.value;
}

/// Discover all modules by scanning top-level sub-directories for a `manifest.json`.
fn discoverModules(alloc: std.mem.Allocator) ![]ManifestModule {
    var list = std.ArrayList(ManifestModule).init(alloc);
    var root = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer root.close();

    var it = root.iterate();

    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        const man = readManifest(alloc, entry.name) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        try list.append(man);
    }

    return list.toOwnedSlice();
}

/// Validates symbols in a module.
fn validateSymbols(alloc: std.mem.Allocator, mods: []const ManifestModule) !void {
    var global = std.StringHashMap([]const u8).init(alloc);
    defer global.deinit();

    for (mods) |m| {
        const init_name = std.fmt.allocPrint(alloc, "{s}_init", .{m.name}) catch unreachable;
        defer alloc.free(init_name);

        var local = std.StringHashMap(void).init(alloc);
        defer local.deinit();

        for (m.symbols) |sym| {
            if (local.contains(sym)) {
                std.debug.panic("duplicate symbol '{s}' in manifest '{s}'", .{ sym, m.name });
            }
            try local.put(sym, {});

            if (global.get(sym)) |owner| {
                std.debug.panic("symbol collision '{s}' between '{s}' and '{s}'", .{ sym, owner, m.name });
            } else {
                global.put(sym, m.name) catch unreachable;
            }
        }

        if (!local.contains(init_name)) {
            std.debug.panic("manifest '{s}' missing required init symbol '{s}'", .{ m.name, init_name });
        }
    }
}

/// Parse a source file and collect all exported symbol names declared via
/// `pub export fn <symbol>`.
fn collectExportedSymbols(alloc: std.mem.Allocator, path: []const u8) ![]const []const u8 {
    const buf = try std.fs.cwd().readFileAlloc(alloc, path, 1 << 20);
    defer alloc.free(buf);

    var list = std.ArrayList([]const u8).init(alloc);
    defer list.deinit();

    const needle = "pub export fn ";
    var pos: usize = 0;

    while (std.mem.indexOfPos(u8, buf, pos, needle)) |idx| {
        const start = idx + needle.len;
        var end = start;

        while (end < buf.len and (std.ascii.isAlphanumeric(buf[end]) or buf[end] == '_')) : (end += 1) {}

        if (end == start) {
            pos = start;
            continue;
        }

        const sym_slice = buf[start..end];
        const sym = try alloc.dupe(u8, sym_slice);
        try list.append(sym);
        pos = end;
    }

    return list.toOwnedSlice();
}

/// Format the expected symbols JSON snippet.
fn buildExpectedSymbolsJson(
    alloc: std.mem.Allocator,
    symbols: []const []const u8,
    missing: []const u8,
) ![]u8 {
    var buf = std.ArrayList(u8).init(alloc);
    try buf.appendSlice("\"symbols\": [");

    for (symbols, 0..) |s, i| {
        if (i != 0) try buf.appendSlice(", ");
        try buf.appendSlice("\"");
        try buf.appendSlice(s);
        try buf.appendSlice("\"");
    }

    if (symbols.len != 0) try buf.appendSlice(", ");
    try buf.appendSlice("\"");
    try buf.appendSlice(missing);
    try buf.appendSlice("\"");
    try buf.appendSlice("]");
    return buf.toOwnedSlice();
}

/// Verify every `pub export` in `path` appears in `m.symbols`.
fn checkExports(
    alloc: std.mem.Allocator,
    path: []const u8,
    m: ManifestModule,
) !void {
    const exports = try collectExportedSymbols(alloc, path);
    defer {
        for (exports) |e| alloc.free(e);
        alloc.free(exports);
    }

    var manifest_set = std.StringHashMap(void).init(alloc);
    defer manifest_set.deinit();
    for (m.symbols) |sym| manifest_set.put(sym, {}) catch unreachable;

    for (exports) |sym| {
        if (manifest_set.contains(sym)) continue;
        const expected = try buildExpectedSymbolsJson(alloc, m.symbols, sym);
        const fname = std.fs.path.basename(path);
        std.debug.panic(
            "{s} exports symbol '{s}' but it is not defined in manifest.json.\nexpected: {s}",
            .{ fname, sym, expected },
        );
    }
}
