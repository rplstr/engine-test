const std = @import("std");
const builtin = @import("builtin");
const proto = @import("proto");
const log = std.log.scoped(.runner);

pub const engine_abi_version = 1;

pub const max_modules = 128;

pub const InitFn = *const fn (*std.mem.Allocator) callconv(.c) void;

pub const DeinitFn = *const fn () callconv(.c) void;

pub const UpdateFn = *const fn (f64) callconv(.c) bool;
fn noUpdate(_: f64) callconv(.c) bool {
    return true;
}

pub fn main() !void {
    if (builtin.os.tag == .wasi or builtin.os.tag == .freestanding)
        @compileError("Dynamic modules are not supported on this target.");

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var bank = try ModuleBank.init(&arena.allocator());
    defer bank.deinit() catch unreachable;

    try loadManifest(arena.allocator(), "modules.json", &bank);

    var last = std.time.nanoTimestamp();
    var dt: f64 = 0;

    while (bank.updateAll(dt)) {
        const now = std.time.nanoTimestamp();
        dt = @as(f64, @floatFromInt(now - last)) / 1e9;
        last = now;
    }
}

const ModuleBank = struct {
    alloc: *const std.mem.Allocator,

    libs: [max_modules]std.DynLib = undefined,

    dein: [max_modules]DeinitFn = undefined,

    update: [max_modules]UpdateFn = undefined,

    offs: [max_modules]u32 = undefined,

    cnt: u32 = 0,

    blob: std.ArrayList(u8),

    pub const Error = error{ TooManyModules, OutOfMemory };

    pub fn init(allocator: *const std.mem.Allocator) !ModuleBank {
        return .{
            .alloc = allocator,
            .blob = try std.ArrayList(u8).initCapacity(allocator.*, 4 * 1024),
        };
    }

    pub fn deinit(self: *ModuleBank) !void {
        while (self.cnt > 0) {
            self.cnt -= 1;
            self.dein[self.cnt]();
            self.libs[self.cnt].close();
        }
        self.blob.deinit();
    }

    pub fn contains(self: *ModuleBank, name: []const u8) bool {
        for (0..@as(usize, self.cnt)) |i|
            if (std.mem.eql(u8, self.getName(i), name)) return true;
        return false;
    }

    pub fn updateAll(self: *ModuleBank, delta: f64) bool {
        for (0..@intCast(self.cnt)) |i| if (!self.update[i](delta)) return false;
        return true;
    }

    pub fn append(self: *ModuleBank, lib: std.DynLib, dein: DeinitFn, update: UpdateFn, name: []const u8) Error!void {
        if (self.cnt == max_modules) {
            log.err("module bank capacity of {d} reached", .{max_modules});
            return error.TooManyModules;
        }

        const off = @as(u32, @intCast(self.blob.items.len));
        try self.blob.appendSlice(name);
        try self.blob.append(0);

        const idx = self.cnt;
        self.libs[idx] = lib;
        self.dein[idx] = dein;
        self.update[idx] = update;
        self.offs[idx] = off;
        self.cnt += 1;
    }

    pub fn getName(self: *ModuleBank, idx: usize) []const u8 {
        const base = self.offs[idx];
        const bytes = self.blob.items[base..];
        const end = std.mem.indexOfScalar(u8, bytes, 0).?;
        return bytes[0..end];
    }
};

fn makeSharedName(allocator: std.mem.Allocator, mod_name: []const u8) ![]u8 {
    const suffix = switch (builtin.os.tag) {
        .windows => ".dll",
        .macos => ".dylib",
        else => ".so",
    };
    const prefix = if (builtin.os.tag == .windows) "" else "lib";
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ prefix, mod_name, suffix });
}

fn makeLibraryPath(allocator: std.mem.Allocator, mod_name: []const u8) ![]u8 {
    const dir = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(dir);
    const file = try makeSharedName(allocator, mod_name);
    defer allocator.free(file);

    return std.fs.path.join(allocator, &.{ dir, "bin", file });
}

fn findSymbol(
    comptime T: type,
    lib: *std.DynLib,
    allocator: std.mem.Allocator,
    comptime f: []const u8,
    mod_name: []const u8,
) error{ MissingSymbol, OutOfMemory }!T {
    const sym = try std.fmt.allocPrintZ(allocator, f, .{mod_name});
    defer allocator.free(sym);
    const ptr = lib.lookup(T, sym) orelse {
        log.err("symbol '{s}' was not found in shared library", .{sym});
        return error.MissingSymbol;
    };
    return ptr;
}

fn findSymbolOpt(
    comptime T: type,
    lib: *std.DynLib,
    allocator: std.mem.Allocator,
    comptime f: []const u8,
    mod_name: []const u8,
) !?T {
    const sym = try std.fmt.allocPrintZ(allocator, f, .{mod_name});
    defer allocator.free(sym);
    return lib.lookup(T, sym);
}

fn loadManifest(allocator: std.mem.Allocator, path: []const u8, bank: *ModuleBank) !void {
    var file = std.fs.cwd().openFile(path, .{}) catch |e|
        switch (e) {
            error.FileNotFound => return,
            else => |err| return err,
        };
    defer file.close();

    const max_json = 1 * 1024 * 1024;
    const buf = try file.readToEndAlloc(allocator, max_json);
    defer allocator.free(buf);

    const Manifest = struct { modules: []const []const u8 = &.{} };
    var parsed = try std.json.parseFromSlice(Manifest, allocator, buf, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    for (parsed.value.modules) |name| {
        if (bank.contains(name) or !isValidName(name)) continue;
        try loadModule(bank, name);
    }
}

fn isValidName(name: []const u8) bool {
    return !(std.mem.containsAtLeast(u8, name, 1, "/") or
        std.mem.containsAtLeast(u8, name, 1, "\\") or
        std.mem.eql(u8, name, ".."));
}

fn loadModule(bank: *ModuleBank, mod_name: []const u8) !void {
    const path = try makeLibraryPath(bank.alloc.*, mod_name);
    defer bank.alloc.free(path);

    std.log.info("opening '{s}' -> {s}", .{ mod_name, path });

    var lib = try std.DynLib.open(path);
    errdefer lib.close();

    std.log.info("opened '{s}'", .{mod_name});

    const init = try findSymbol(InitFn, &lib, bank.alloc.*, "{s}_init", mod_name);
    const dein = try findSymbol(DeinitFn, &lib, bank.alloc.*, "{s}_deinit", mod_name);
    const upd = try findSymbolOpt(UpdateFn, &lib, bank.alloc.*, "{s}_update", mod_name) orelse noUpdate;

    init(@constCast(bank.alloc));
    errdefer dein();

    try bank.append(lib, dein, upd, mod_name);
}
