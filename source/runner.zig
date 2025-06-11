const std = @import("std");
const builtin = @import("builtin");

/// A function pointer to a module's initialization function.
pub const init_fn = *const fn (*std.mem.Allocator) callconv(.C) void;

/// A function pointer to a module's deinitialization function.
pub const deinit_fn = *const fn () callconv(.C) void;

/// Maximum number of modules that can be loaded at once.
pub const max_modules = 128;

pub fn main() !void {
    if (builtin.os.tag == .wasi or builtin.os.tag == .freestanding)
        @compileError("Dynamic modules are not supported on this target.");

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var bank = try ModuleBank.init(&arena.allocator());
    defer bank.deinit() catch unreachable;

    try loadManifest(arena.allocator(), "modules.json", &bank);
}

/// Compact store for loaded modules.
pub const ModuleBank = struct {
    allocator: *const std.mem.Allocator,
    libs: [max_modules]std.DynLib = undefined,
    deinits: [max_modules]deinit_fn = undefined,
    name_offs: [max_modules]u32 = undefined,
    count: u32 = 0,
    blob: std.ArrayList(u8),

    /// Creates an empty bank that allocates from `allocator`.
    pub fn init(allocator: *const std.mem.Allocator) !ModuleBank {
        return ModuleBank{
            .allocator = allocator,
            .blob = try std.ArrayList(u8).initCapacity(allocator.*, 4096),
        };
    }

    /// Calls every `deinit`, closes every library, and frees all memory.
    pub fn deinit(self: *ModuleBank) !void {
        var i: usize = self.count;
        while (i > 0) : (i -= 1) {
            self.deinits[i - 1]();
            self.libs[i - 1].close();
        }
        self.blob.deinit();
    }

    /// Returns `true` when `name` already exists in the bank.
    pub fn contains(self: *ModuleBank, name: []const u8) bool {
        for (0..self.count) |idx| {
            if (std.mem.eql(u8, self.getName(idx), name)) return true;
        }
        return false;
    }

    /// Stores a fully-initialised module.
    pub fn append(self: *ModuleBank, lib: std.DynLib, deinit_fn_ptr: deinit_fn, name: []const u8) !void {
        if (self.count == max_modules) return error.TooManyModules;

        const start = @as(u32, @intCast(self.blob.items.len));
        try self.blob.appendSlice(name);
        try self.blob.append(0);

        const idx = self.count;
        self.libs[idx] = lib;
        self.deinits[idx] = deinit_fn_ptr;
        self.name_offs[idx] = start;
        self.count += 1;
    }

    /// Returns the stored module name at `idx`.
    pub fn getName(self: *ModuleBank, idx: usize) []const u8 {
        const off = self.name_offs[idx];
        const slice = self.blob.items[off..];
        return slice[0..std.mem.indexOf(u8, slice, "\x00").?];
    }
};

/// Composes the platform-specific shared-library filename.
///
/// `"engine"` becomes `"libengine.so"` on Linux, `"engine.dll"` on Windows,
/// and `"engine.dylib"` on macOS.
fn makeSharedName(allocator: std.mem.Allocator, mod: []const u8) ![]u8 {
    const suffix = switch (builtin.os.tag) {
        .windows => ".dll",
        .macos => ".dylib",
        else => ".so",
    };
    const prefix = switch (builtin.os.tag) {
        .windows => "",
        else => "lib",
    };
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ prefix, mod, suffix });
}

/// Returns an absolute path to the module’s shared library.
fn makeLibraryPath(allocator: std.mem.Allocator, mod: []const u8) ![]u8 {
    const dir = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(dir);
    const name = try makeSharedName(allocator, mod);
    defer allocator.free(name);
    return std.fs.path.join(allocator, &.{ dir, name });
}

/// Looks up a formatted symbol within `lib`.
fn findSymbol(comptime T: type, lib: *std.DynLib, allocator: std.mem.Allocator, comptime fmt: []const u8, mod: []const u8) !T {
    const symbol = try std.fmt.allocPrintZ(allocator, fmt, .{mod});
    defer allocator.free(symbol);
    return lib.lookup(T, symbol) orelse return error.MissingSymbol;
}

/// Reads a JSON manifest of the form
///
/// ```json
/// { "modules": [ "engine", "render", "audio" ] }
/// ```
///
/// Every string inside `"modules"` is passed to `loadModule`.
/// Duplicates are ignored.
fn loadManifest(
    allocator: std.mem.Allocator,
    path: []const u8,
    bank: *ModuleBank,
) !void {
    var file = std.fs.cwd().openFile(path, .{}) catch |e|
        switch (e) {
            error.FileNotFound => return,
            else => |err| return err,
        };
    defer file.close();

    const buf = try file.readToEndAlloc(allocator, 1 * 1024 * 1024);
    defer allocator.free(buf);

    const Manifest = struct { modules: []const []const u8 = &.{} };
    var parsed = try std.json.parseFromSlice(Manifest, allocator, buf, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    for (parsed.value.modules) |name| {
        if (bank.contains(name)) continue;
        try loadModule(bank, name);
    }
}
/// Dynamically loads `mod`, runs `<mod>_init`, and stores the handle.
fn loadModule(bank: *ModuleBank, mod: []const u8) !void {
    const lib_path = try makeLibraryPath(bank.allocator.*, mod);
    defer bank.allocator.free(lib_path);

    std.log.info("opening library for module '{s}' -> {s}", .{ mod, lib_path });

    var lib = try std.DynLib.open(lib_path);
    errdefer lib.close();

    const init = try findSymbol(init_fn, &lib, bank.allocator.*, "{s}_init", mod);
    const deinit = try findSymbol(deinit_fn, &lib, bank.allocator.*, "{s}_deinit", mod);

    init(@constCast(bank.allocator));
    errdefer deinit();

    try bank.append(lib, deinit, mod);
}
