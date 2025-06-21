const std = @import("std");

pub const InterfaceID = u64;

pub const HostInterface = extern struct {
    context: *anyopaque,
    register_interface: *const fn (ctx: *anyopaque, iid: InterfaceID, ptr: *const anyopaque) callconv(.c) void,
    query_interface: *const fn (ctx: *anyopaque, iid: InterfaceID) callconv(.c) ?*const anyopaque,
};

pub const module_init_fn_name = "attach";
pub const ModuleInitFn = fn (*const HostInterface) callconv(.c) void;
