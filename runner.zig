const std = @import("std");
const builtin = @import("builtin");
const host = @import("host");

const Host = struct {
    allocator: std.mem.Allocator,
    registry: std.HashMap(host.InterfaceID, *const anyopaque, std.hash_map.AutoContext(host.InterfaceID), 80),
    host_api: host.HostInterface,
    libs: std.ArrayList(std.DynLib),

    pub fn init(self: *Host, allocator: std.mem.Allocator) void {
        self.* = .{
            .allocator = allocator,
            .registry = std.HashMap(host.InterfaceID, *const anyopaque, std.hash_map.AutoContext(host.InterfaceID), 80).init(allocator),
            .host_api = undefined,
            .libs = std.ArrayList(std.DynLib).init(allocator),
        };
        self.host_api = .{
            .context = self,
            .register_interface = &register,
            .query_interface = &query,
        };
    }

    pub fn deinit(self: *Host) void {
        for (self.libs.items) |*lib| {
            lib.close();
        }
        self.libs.deinit();
        self.registry.deinit();
        self.* = undefined;
    }

    fn register(ctx: *anyopaque, iid: host.InterfaceID, ptr: *const anyopaque) callconv(.c) void {
        const self: *Host = @ptrCast(@alignCast(ctx));
        std.log.info("registering interface {any} with implementation at {p}", .{ iid, ptr });
        self.registry.put(iid, ptr) catch |err| {
            std.log.err("failed to register interface {any}: {s}", .{ iid, @errorName(err) });
        };
    }

    fn query(ctx: *anyopaque, iid: host.InterfaceID) callconv(.c) ?*const anyopaque {
        const self: *Host = @ptrCast(@alignCast(ctx));
        std.log.info("querying interface {any}", .{iid});
        const ptr = self.registry.get(iid);
        if (ptr == null) {
            std.log.warn("interface {any} not found", .{iid});
        }
        return ptr;
    }
};

fn parseModuleManifest(allocator: std.mem.Allocator, path: []const u8) ![][]const u8 {
    const manifest_contents = try std.fs.cwd().readFileAlloc(allocator, path, 1 * 1024 * 1024);
    defer allocator.free(manifest_contents);

    const Manifest = struct { modules: []const []const u8 };
    var parsed = try std.json.parseFromSlice(Manifest, allocator, manifest_contents, .{});
    defer parsed.deinit();

    const paths = parsed.value.modules;
    const dupe_paths = try allocator.alloc([]const u8, paths.len);
    errdefer allocator.free(dupe_paths);

    for (paths, 0..) |p, i| {
        dupe_paths[i] = try allocator.dupe(u8, p);
    }
    return dupe_paths;
}

pub fn main() !void {
    if (builtin.os.tag == .wasi or builtin.os.tag == .freestanding)
        @compileError("Dynamic modules are not supported on this target.");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var host_state: Host = undefined;
    Host.init(&host_state, allocator);
    defer host_state.deinit();

    const module_paths = try parseModuleManifest(allocator, "modules.json");
    defer {
        for (module_paths) |path| {
            allocator.free(path);
        }
        allocator.free(module_paths);
    }

    std.log.info("found {d} modules", .{module_paths.len});
    for (module_paths) |path| {
        std.log.info("loading module '{s}'", .{path});
        var lib = try std.DynLib.open(path);

        const init_fn = lib.lookup(*const host.ModuleInitFn, host.module_init_fn_name) orelse {
            std.log.err("module '{s}' is missing the required '{s}' entry point, skipping.", .{ path, host.module_init_fn_name });
            lib.close();
            continue;
        };

        init_fn(&host_state.host_api);
        try host_state.libs.append(lib);
    }
}
