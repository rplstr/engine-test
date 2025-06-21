const std = @import("std");

pub fn module(b: *std.Build) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("host/interface.zig"),
    });
}
