const std = @import("std");

// Parse flags from an ArgIterator according to the provided Flags struct.
pub fn parse(comptime Flags: type, args: *std.process.ArgIterator) !Flags {
    std.debug.assert(args.skip());
    return parseIter(Flags, args, argPeek, argNext);
}
fn argPeek(args: *std.process.ArgIterator) ?[]const u8 {
    var argsCopy = args.*;
    return argsCopy.nextPosix() orelse null;
}
fn argNext(args: *std.process.ArgIterator) ?[]const u8 {
    return std.process.ArgIterator.nextPosix(args) orelse null;
}

pub fn parseIter(
    comptime Flags: type,
    context: anytype,
    peek: fn (@TypeOf(context)) ?[]const u8,
    next: fn (@TypeOf(context)) ?[]const u8,
) !Flags {
    var flags: Flags = .{};

    while (peek(context)) |arg| {
        if (arg.len < 2 or !std.mem.startsWith(u8, arg, "-")) break;
        std.debug.assert(arg.ptr == (next(context) orelse unreachable).ptr);
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
                        const flag_arg = if (i + 2 < arg.len)
                            arg[i + 2 ..]
                        else
                            next(context) orelse return error.MissingArgument;

                        if (T == []const u8) {
                            @field(flags, field.name) = flag_arg;
                        } else {
                            @field(flags, field.name) = switch (@typeInfo(T)) {
                                .Int => try std.fmt.parseInt(T, flag_arg, 10),
                                .Float => try std.fmt.parseFloat(T, flag_arg),
                                else => @compileError("Unsupported flag type '" ++ @typeName(field.field_type) ++ "'"),
                            };
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
    return flags;
}

fn Unwrap(comptime T: type) type {
    return if (@typeInfo(T) == .Optional) std.meta.Child(T) else T;
}

fn parseTest(comptime Flags: type, args: []const []const u8) !Flags {
    var argsV = args;
    return parseIter(Flags, &argsV, testPeek, testNext);
}
fn testPeek(args: *[]const []const u8) ?[]const u8 {
    if (args.*.len == 0) return null;
    return args.*[0];
}
fn testNext(args: *[]const []const u8) ?[]const u8 {
    if (testPeek(args)) |arg| {
        args.* = args.*[1..];
        return arg;
    } else {
        return null;
    }
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
    try expectEqualStrings(flags.s, "default value");
}

test "string flag - separated" {
    const flags = try parseTest(
        struct { s: []const u8 = "default value" },
        &.{ "-s", "separate value" },
    );
    try expectEqualStrings(flags.s, "separate value");
}

test "string flag - combined" {
    const flags = try parseTest(
        struct { s: []const u8 = "default value" },
        &.{"-scombined value"},
    );
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
