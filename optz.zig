const std = @import("std");
const Allocator = std.mem.Allocator;

// Parse flags from an ArgIterator according to the provided Flags struct. Skips the first arg
pub fn parse(allocator: Allocator, comptime Flags: type, args: *std.process.ArgIterator) !Flags {
    std.debug.assert(args.skip());
    return parseRaw(allocator, Flags, args);
}

// Parse flags from an ArgIterator according to the provided Flags struct
pub fn parseRaw(allocator: Allocator, comptime Flags: type, args: *std.process.ArgIterator) !Flags {
    return parseIter(allocator, Flags, args, argPeek, argAdvance);
}

fn argPeek(args: *std.process.ArgIterator) ?[]const u8 {
    var argsCopy = args.*;
    return argsCopy.next() orelse null;
}
fn argAdvance(args: *std.process.ArgIterator) void {
    std.debug.assert(args.skip());
}

const ParseError = error{
    InvalidFlag,
    MissingParameter,
    InvalidCharacter,
    Overflow,
    OutOfMemory,
};

pub fn parseIter(
    allocator: Allocator,
    comptime Flags: type,
    context: anytype,
    peek: fn (@TypeOf(context)) ?[]const u8,
    advance: fn (@TypeOf(context)) void,
) ParseError!Flags {
    var flags: Flags = .{};

    while (peek(context)) |arg| {
        if (arg.len < 2 or !std.mem.startsWith(u8, arg, "-")) break;
        advance(context);
        if (std.mem.eql(u8, arg, "--")) break;

        arg_flags: for (arg[1..], 0..) |opt, i| {
            inline for (std.meta.fields(Flags)) |field| {
                if (field.name.len != 1) {
                    @compileError("An argument name must be a single character");
                }

                if (opt == field.name[0]) {
                    const T = Unwrap(field.type);
                    if (T == bool) {
                        @field(flags, field.name) = true;
                    } else {
                        var param: []const u8 = undefined;
                        if (i + 2 < arg.len) {
                            param = arg[i + 2 ..];
                        } else {
                            param = peek(context) orelse {
                                return error.MissingParameter;
                            };
                            advance(context);
                        }
                        if (T == []const u8) {
                            @field(flags, field.name) = try allocator.dupe(u8, param);
                        } else {
                            @field(flags, field.name) = switch (@typeInfo(T)) {
                                .int => try std.fmt.parseInt(T, param, 10),
                                .float => try std.fmt.parseFloat(T, param),
                                else => @compileError("Unsupported flag type '" ++ @typeName(field.type) ++ "'"),
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

    // Dupe all strings
    const fields = std.meta.fields(Flags);
    inline for (fields, 0..) |field, i| {
        if (field.type == []const u8) {
            @field(flags, field.name) = allocator.dupe(u8, @field(flags, field.name)) catch |err| {
                // Free all previously allocated strings
                comptime var j = i;
                inline while (j > 0) {
                    j -= 1;
                    if (fields[j].type == []const u8) {
                        allocator.free(@field(flags, fields[j].name));
                    }
                }
                return err;
            };
        }
    }

    return flags;
}

fn Unwrap(comptime T: type) type {
    return if (@typeInfo(T) == .optional) std.meta.Child(T) else T;
}

fn parseTest(comptime Flags: type, args: []const []const u8) !Flags {
    var argsV = args;
    return parseIter(std.testing.allocator, Flags, &argsV, testPeek, testAdvance);
}
fn testPeek(args: *[]const []const u8) ?[]const u8 {
    if (args.*.len == 0) return null;
    return args.*[0];
}
fn testAdvance(args: *[]const []const u8) void {
    args.* = args.*[1..];
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "arg iterator" {
    var args = try std.process.argsWithAllocator(std.testing.allocator);
    defer args.deinit();
    _ = try parse(std.testing.allocator, struct {}, &args);
}

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

test "bool and string flags" {
    {
        const flags = try parseTest(
            struct {
                b: bool = false,
                s: []const u8 = "",
            },
            &.{ "-s", "foo" },
        );
        defer std.testing.allocator.free(flags.s);
        try expectEqual(flags.b, false);
        try expectEqualStrings(flags.s, "foo");
    }

    {
        const flags = try parseTest(
            struct {
                b: bool = false,
                s: []const u8 = "",
            },
            &.{ "-b", "-s", "bar" },
        );
        defer std.testing.allocator.free(flags.s);
        try expectEqual(flags.b, true);
        try expectEqualStrings(flags.s, "bar");
    }
}
