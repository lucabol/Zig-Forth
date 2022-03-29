const std = @import("std");

const Vm = struct { state: i32 = 0, in: std.fs.File.Reader, out: std.fs.File.Writer };

const Ops = struct {
    inline fn double(vm: *Vm) !void {
        vm.state *= 2;
    }
    inline fn plus1(vm: *Vm) !void {
        vm.state += 1;
    }
    inline fn notFound(vm: *Vm) !void {
        try vm.out.print("{s}\n", .{"Word not found."});
    }
    inline fn bye(_: *Vm) !void {
        std.process.exit(0);
    }
    inline fn @"."(vm: *Vm) !void {
        try vm.out.print("{d} ", .{vm.state});
    }
};

inline fn shellLoop(stdin: std.fs.File.Reader, stdout: std.fs.File.Writer) !void {
    const max_input = 1024;
    var input_buffer: [max_input]u8 = undefined;
    var vm = Vm{
        .in = stdin,
        .out = stdout,
    };

    while (true) {
        try stdout.print("> ", .{});

        var input_str = (try stdin.readUntilDelimiterOrEof(input_buffer[0..], '\n')) orelse {
            try stdout.print("\n", .{});
            return;
        };

        if (input_str.len == 0) continue;
        var words = std.mem.tokenize(u8, input_str, " ");

        while (words.next()) |word| { // (*)
            const token = findToken(word) orelse Token.notFound;
            execToken(&vm, token);
        }
        std.log.info("{}", .{vm.state});
    }
}

inline fn findToken(word: []const u8) ?Token {
    inline for (@typeInfo(Token).Enum.fields) |enField| {
        if (std.mem.eql(u8, enField.name, word))
            return @field(Token, enField.name);
    }
    return null;
}

inline fn execToken(vm: *Vm, tok: Token) void {
    inline for (@typeInfo(Token).Enum.fields) |enField| {
        const enumValue = @field(Token, enField.name);
        if (enumValue == tok) {
            const empty = .{};
            _ = @call(empty, @field(Ops, @tagName(enumValue)), .{vm}) catch unreachable;
        }
    }
}

const Token = GenerateTokenEnumType(Ops);

fn GenerateTokenEnumType(comptime T: type) type {
    const fieldInfos = std.meta.declarations(T);
    var enumDecls: [fieldInfos.len]std.builtin.TypeInfo.EnumField = undefined;
    var decls = [_]std.builtin.TypeInfo.Declaration{};
    inline for (fieldInfos) |field, i| {
        enumDecls[i] = .{ .name = field.name, .value = i };
    }
    return @Type(.{
        .Enum = .{
            .layout = .Auto,
            .tag_type = u8,
            .fields = &enumDecls,
            .decls = &decls,
            .is_exhaustive = true,
        },
    });
}

pub fn main() !u8 {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    try stdout.print("*** Hello, I am a Forth shell! ***\n", .{});

    try shellLoop(stdin, stdout);

    return 0;
}
