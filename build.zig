const std = @import("std");

pub fn build(b: *std.Build) void {
    b.addModule(.{
        .name = "optz",
        .source_file = .{ .path = "optz.zig" },
    });

    const test_step = b.addTest(.{
        .root_source_file = .{ .path = "optz.zig" },
    });
    b.step("test", "Run library tests").dependOn(&test_step.step);
}
