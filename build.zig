const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b.addModule("optz", .{
        .root_source_file = b.path("optz.zig"),
    });
}
