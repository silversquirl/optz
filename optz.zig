const std = @import("std");
const Allocator = std.mem.Allocator;

// Parse flags from an ArgIterator according to the provided Flags struct.
pub fn parse(allocator: Allocator, comptime Flags: type, args: *std.process.ArgIterator) !Flags {
    std.debug.assert(args.skip());
    return parseIter(allocator, Flags, args, argPeek, argAdvance);
}
fn argPeek(allocator: Allocator, args: *std.process.ArgIterator) NextError!?[]const u8 {
    var argsCopy = args.*;
    return try argsCopy.next(allocator);
}
fn argAdvance(args: *std.process.ArgIterator) void {
    std.debug.assert(args.skip());
}

pub const NextError = std.process.ArgIterator.NextError;

pub fn parseIter(
    allocator: Allocator,
    comptime Flags: type,
    context: anytype,
    peek: fn (Allocator, @TypeOf(context)) NextError!?[]const u8,
    advance: fn (@TypeOf(context)) void,
) !Flags {
    var flags: Flags = .{};

    while (try peek(allocator, context)) |arg| {
        defer allocator.free(arg);
        if (arg.len < 2 or !std.mem.startsWith(u8, arg, "-")) break;
        advance(context);
        if (std.mem.eql(u8, arg, "--")) break;

        arg_flags: for (arg[1..]) |opt, i| {
            inline for (std.meta.fields(Flags)) |field| {
                if (field.name.len != 1) {
                    @compileError("An argument name must be a single character");
                }

                if (opt == field.name[0]) {
                    const T = Unwrap(field.field_type);
                    if (T == bool) {
                        @field(flags, field.name) = true;
                    } else {
                        var param: []const u8 = undefined;
                        if (i + 2 < arg.len) {
                            param = try allocator.dupe(u8, arg[i + 2 ..]);
                        } else {
                            param = (try peek(allocator, context)) orelse {
                                return error.MissingParameter;
                            };
                            advance(context);
                        }
                        errdefer allocator.free(param);

                        if (T == []const u8) {
                            @field(flags, field.name) = param;
                        } else {
                            @field(flags, field.name) = switch (@typeInfo(T)) {
                                .Int => try std.fmt.parseInt(T, param, 10),
                                .Float => try std.fmt.parseFloat(T, param),
                                else => @compileError("Unsupported flag type '" ++ @typeName(field.field_type) ++ "'"),
                            };
                            allocator.free(param);
                        }

                        // Ensure we don't try to parse any more flags from this arg
                        break :arg_flags;
                    }

                    break;
                }
            } else {
                return error.InvalidFlag;
            }
        }
    }

    // Dupe all default strings
    inline for (std.meta.fields(Flags)) |field| {
        if (field.field_type != []const u8) continue;
        if (@field(flags, field.name).ptr == field.default_value.?.ptr) {
            @field(flags, field.name) = try allocator.dupe(u8, @field(flags, field.name));
        }
    }

    return flags;
}

fn Unwrap(comptime T: type) type {
    return if (@typeInfo(T) == .Optional) std.meta.Child(T) else T;
}

fn parseTest(comptime Flags: type, args: []const []const u8) !Flags {
    var argsV = args;
    return parseIter(std.testing.allocator, Flags, &argsV, testPeek, testAdvance);
}
fn testPeek(allocator: Allocator, args: *[]const []const u8) Allocator.Error!?[]const u8 {
    if (args.*.len == 0) return null;
    return try allocator.dupe(u8, args.*[0]);
}
fn testAdvance(args: *[]const []const u8) void {
    args.* = args.*[1..];
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "bool flag - default" {
    const flags = try parseTest(
        struct { b: bool = false },
        &.{},
    );
    try expect(!flags.b);
}

test "bool flag - specified" {
    const flags = try parseTest(
        struct { b: bool = false },
        &.{"-b"},
    );
    try expect(flags.b);
}

test "string flag - default" {
    const flags = try parseTest(
        struct { s: []const u8 = "default value" },
        &.{},
    );
    defer std.testing.allocator.free(flags.s);
    try expectEqualStrings(flags.s, "default value");
}

test "string flag - separated" {
    const flags = try parseTest(
        struct { s: []const u8 = "default value" },
        &.{ "-s", "separate value" },
    );
    defer std.testing.allocator.free(flags.s);
    try expectEqualStrings(flags.s, "separate value");
}

test "string flag - combined" {
    const flags = try parseTest(
        struct { s: []const u8 = "default value" },
        &.{"-scombined value"},
    );
    defer std.testing.allocator.free(flags.s);
    try expectEqualStrings(flags.s, "combined value");
}

test "int flag - default" {
    const flags = try parseTest(
        struct { s: u8 = 7 },
        &.{},
    );
    try expectEqual(flags.s, 7);
}

test "int flag - separated" {
    const flags = try parseTest(
        struct { s: u8 = 7 },
        &.{ "-s", "40" },
    );
    try expectEqual(flags.s, 40);
}

test "int flag - combined" {
    const flags = try parseTest(
        struct { s: u8 = 7 },
        &.{"-s70"},
    );
    try expectEqual(flags.s, 70);
}

test "float flag - default" {
    const flags = try parseTest(
        struct { s: f32 = 9.6 },
        &.{},
    );
    try expectEqual(flags.s, 9.6);
}

test "float flag - separated" {
    const flags = try parseTest(
        struct { s: f32 = 9.6 },
        &.{ "-s", "4.2" },
    );
    try expectEqual(flags.s, 4.2);
}

test "float flag - combined" {
    const flags = try parseTest(
        struct { s: f32 = 9.6 },
        &.{"-s0.36"},
    );
    try expectEqual(flags.s, 0.36);
}
