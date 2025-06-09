const std = @import("std");
const builtin = @import("builtin");

const InitFn = *const fn () void;

fn sharedName(alloc: std.mem.Allocator, mod: []const u8) ![]u8 {
    const ext = switch (builtin.os.tag) {
        .windows => ".dll",
        .macos => ".dylib",
        else => ".so",
    };
    const pref = switch (builtin.os.tag) {
        .windows => "",
        else => "lib",
    };
    return std.fmt.allocPrint(alloc, "{s}{s}{s}", .{ pref, mod, ext });
}

fn libPath(alloc: std.mem.Allocator, mod: []const u8) ![]u8 {
    const dir = try std.fs.selfExeDirPathAlloc(alloc);
    defer alloc.free(dir);

    const name = try sharedName(alloc, mod);
    defer alloc.free(name);

    return std.fs.path.join(alloc, &.{ dir, name });
}

fn loadModule(
    alloc: std.mem.Allocator,
    mods: *std.ArrayList(std.DynLib),
    name: []const u8,
) !void {
    const path = try libPath(alloc, name);
    defer alloc.free(path);

    var lib = try std.DynLib.open(path);
    try mods.append(lib);

    const init = lib.lookup(InitFn, "module_init").?;
    init();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var libs = std.ArrayList(std.DynLib).init(alloc);
    defer {
        for (libs.items) |*l| l.close();
        libs.deinit();
    }

    const argv = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, argv);

    const want = if (argv.len > 1) argv[1] else "engine";

    try loadModule(alloc, &libs, "engine");

    if (std.mem.eql(u8, want, "engine") == false) {
        try loadModule(alloc, &libs, want);
    }
}
