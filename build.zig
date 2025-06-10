const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const modules = discoverModules(b.allocator) catch |e| std.debug.panic("module discovery failed: {}", .{e});

    const exe = addRunner(b, target, optimize);
    b.installArtifact(exe);
    const map = compileModules(b, modules, target, optimize);
    resolveDeps(modules, map);

    b.default_step.dependOn(&exe.step);
}

/// Add the `runner` executable build step. Returns the compile step so
/// the caller can attach dependencies.
fn addRunner(b: *std.Build, target: std.Build.ResolvedTarget, opt: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "runner",
        .root_source_file = b.path("source/runner.zig"),
        .target = target,
        .optimize = opt,
    });

    exe.linkLibC();
    return exe;
}

/// Compile all discovered modules as dynamic libraries, install them, and
/// return a mapping from module names to their compile steps.
fn compileModules(b: *std.Build, mods: []const ManifestModule, target: std.Build.ResolvedTarget, opt: std.builtin.OptimizeMode) std.StringHashMap(*std.Build.Step.Compile) {
    var map = std.StringHashMap(*std.Build.Step.Compile).init(b.allocator);
    map.ensureTotalCapacity(@intCast(mods.len)) catch unreachable;

    for (mods) |m| {
        const src = if (m.root_source_file.len != 0)
            std.fs.path.join(b.allocator, &.{ m.name, m.root_source_file }) catch unreachable
        else
            std.fmt.allocPrint(b.allocator, "{s}/{s}.zig", .{ m.name, m.name }) catch unreachable;

        const mod = b.addModule(m.name, .{
            .root_source_file = b.path(src),
            .target = target,
            .optimize = opt,
        });

        const lib = b.addLibrary(.{
            .name = m.name,
            .root_module = mod,
            .linkage = .dynamic,
            .version = m.version,
        });
        lib.linkLibC();

        const inst = b.addInstallArtifact(lib, .{});

        const step_name = m.name;
        const step_desc = std.fmt.allocPrint(b.allocator, "Build {s} module only", .{m.name}) catch unreachable;
        const step = b.step(step_name, step_desc);
        step.dependOn(&inst.step);

        map.putAssumeCapacity(m.name, lib);
    }

    return map;
}

/// Link and import dependencies between previously compiled modules
/// according to their manifests.
fn resolveDeps(mods: []const ManifestModule, map: std.StringHashMap(*std.Build.Step.Compile)) void {
    for (mods) |m| {
        const lib = map.get(m.name).?;
        for (m.deps) |d| {
            const dep = map.get(d) orelse std.debug.panic("unknown dependency '{s}' for '{s}'", .{ d, m.name });
            lib.linkLibrary(dep);
            lib.root_module.addImport(d, dep.root_module);
        }
    }
}

/// Module descriptor parsed from `manifest.json` found in each module directory.
///
/// ```json
/// manifest.json
/// {
///   "name": "engine",
///   "version": {"major":1,"minor":0,"patch":0},
///   "root_source_file": "custom.zig",
///   "deps": ["core"]
/// }
/// ```
///
/// * `name`     – folder name & library name.
/// * `root_source_file` – entry .zig file relative to the module directory (defaults to `<name>.zig`).
/// * `version`          – semantic version used for `.so/.dll` version info.
/// * `deps`             – other module names this module links against.
const ManifestModule = struct {
    name: []const u8,
    root_source_file: []const u8 = "",
    version: std.SemanticVersion = .{ .major = 1, .minor = 0, .patch = 0 },
    deps: []const []const u8 = &.{},
};

/// Read and parse `dir_name/manifest.json` and return a validated
/// `ManifestModule` description. Files larger than 256 KiB are rejected.
fn readManifest(alloc: std.mem.Allocator, dir_name: []const u8) !ManifestModule {
    const path = try std.fs.path.join(alloc, &.{ dir_name, "manifest.json" });
    defer alloc.free(path);
    const buf = try std.fs.cwd().readFileAlloc(alloc, path, 1 << 18);
    const parsed = try std.json.parseFromSlice(ManifestModule, alloc, buf, .{});
    return parsed.value;
}

/// Scan the project root for sub-directories containing `manifest.json`
/// and return a heap-allocated slice of all discovered module descriptors.
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
