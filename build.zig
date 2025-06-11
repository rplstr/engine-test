const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const mods = discoverAll(b.allocator) catch |err| std.debug.panic("failed to discover modules: {any}", .{err});
    defer b.allocator.free(mods);

    const sorted = topoSort(b.allocator, mods) catch |err| std.debug.panic("failed to sort modules: {any}", .{err});

    var mod_step = std.StringHashMap(*std.Build.Step.Compile).init(b.allocator);
    compileAll(b, target, optimize, sorted, &mod_step);

    const exe = b.addExecutable(.{
        .name = "runner",
        .root_source_file = b.path("source/runner.zig"),
        .optimize = optimize,
        .target = target,
    });
    exe.linkLibC();

    linkAll(exe, sorted, &mod_step);

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the application").dependOn(&run_cmd.step);
}

/// Optional lists of system libraries, keyed by host OS.
const SysLibs = struct {
    windows: ?[]const []const u8 = null,
    linux: ?[]const []const u8 = null,
    macos: ?[]const []const u8 = null,
};

/// One module description exactly as it appears in `manifest.json`.
const Module = struct {
    name: []const u8,
    root_source_file: []const u8,
    dependencies: []const []const u8,
    system_libraries: SysLibs = .{},
    version: std.SemanticVersion = .{ .major = 1, .minor = 0, .patch = 0 },
};

/// Recursively scans the CWD for directories that contain `manifest.json`
/// and returns an owned slice of parsed `Mod` records.
fn discoverAll(allocator: std.mem.Allocator) ![]Module {
    var out = std.ArrayList(Module).init(allocator);
    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;

        const mod = readModule(allocator, entry.name) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };

        try out.append(mod);
    }

    return out.toOwnedSlice();
}

/// Parses `<dir>/manifest.json` and returns a `Mod` value.
///
/// Allocation mistakes are cleaned up on the caller side.
fn readModule(alloc: std.mem.Allocator, dir: []const u8) !Module {
    const path = try std.fs.path.join(alloc, &.{ dir, "manifest.json" });
    defer alloc.free(path);

    const buf = try std.fs.cwd().readFileAlloc(alloc, path, 1 * 1024 * 1024);

    const parsed = try std.json.parseFromSlice(Module, alloc, buf, .{ .ignore_unknown_fields = true });

    return parsed.value;
}
/// Returns a topologically-sorted copy of `mods`.
fn topoSort(alloc: std.mem.Allocator, mods: []Module) ![]Module {
    var idx_map = std.StringHashMap(usize).init(alloc);
    try idx_map.ensureTotalCapacity(@intCast(mods.len));

    for (mods, 0..) |m, i| {
        try idx_map.putNoClobber(m.name, i); // You have a duplicate name.
    }

    var in_degrees = try alloc.alloc(u32, mods.len);
    @memset(in_degrees, 0);

    for (mods) |m| for (m.dependencies) |d| {
        const j = idx_map.get(d) orelse return error.UnknownModule;
        in_degrees[j] += 1;
    };

    var queue = std.ArrayList(usize).init(alloc);
    for (in_degrees, 0..) |deg, i| if (deg == 0) queue.append(i) catch unreachable;

    var out = std.ArrayList(Module).init(alloc);
    while (queue.pop()) |i| {
        try out.append(mods[i]);
        for (mods[i].dependencies) |d| {
            const j = idx_map.get(d).?;
            in_degrees[j] -= 1;
            if (in_degrees[j] == 0) queue.append(j) catch unreachable;
        }
    }

    if (out.items.len != mods.len) return error.DependencyCycle;
    return out.toOwnedSlice();
}

/// Returns `true` when the OS requires static linkage (WASI / freestanding).
fn isStaticBuild(os_tag: std.Target.Os.Tag) bool {
    return switch (os_tag) {
        .wasi, .freestanding => true,
        else => false,
    };
}

/// Emits one `lib` step per module and stores pointers in `steps`.
fn compileAll(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    mods: []Module,
    steps: *std.StringHashMap(*std.Build.Step.Compile),
) void {
    const static = isStaticBuild(target.result.os.tag);

    for (mods) |mod| {
        const module_path = b.pathJoin(&.{ mod.name, mod.root_source_file });
        const root = b.addModule(mod.name, .{
            .root_source_file = b.path(module_path),
            .optimize = optimize,
            .target = target,
        });
        const lib = b.addLibrary(.{
            .name = mod.name,
            .root_module = root,
            .linkage = if (static) .static else .dynamic,
            .version = mod.version,
        });
        lib.linkLibC();
        linkSystemLibraries(mod, lib, target.result.os.tag);
        if (!static) b.installArtifact(lib);
        steps.put(mod.name, lib) catch unreachable;
    }
}

/// Resolves inter-module dependencies and links into the runner when static.
fn linkAll(exe: *std.Build.Step.Compile, mods: []const Module, steps: *std.StringHashMap(*std.Build.Step.Compile)) void {
    const static = isStaticBuild(exe.rootModuleTarget().os.tag);
    for (mods) |m| {
        const lib = steps.get(m.name).?;
        for (m.dependencies) |d| {
            const dep = steps.get(d) orelse std.debug.panic("unknown dependency '{s}'", .{d});
            lib.root_module.addImport(d, dep.root_module);
            lib.linkLibrary(dep);
        }
        if (static) exe.linkLibrary(lib);
    }
}

/// Links the per-OS system libraries declared in `mod`.
fn linkSystemLibraries(mod: Module, lib: *std.Build.Step.Compile, os: std.Target.Os.Tag) void {
    const list = switch (os) {
        .windows => mod.system_libraries.windows,
        .linux => mod.system_libraries.linux,
        .macos => mod.system_libraries.macos,
        else => null,
    } orelse return;

    for (list) |name| lib.linkSystemLibrary(name);
}
