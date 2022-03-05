 ## Test

```zig


```

 A test

```zig

const std = @import("std");

```

 Another test

```zig

const Vm = struct {
    state: i32 = 0,

    inline fn op_double(this: *Vm) void {
        this.state = this.state * 2;
    }
    inline fn op_plus1(this: *Vm) void {
        this.state = this.state + 1;
    }
    inline fn op_notFound(_: *Vm) void {
        std.log.info("{s}", .{"Word not found."});
    }
    inline fn op_bye(_: *Vm) void {
        std.process.exit(0);
    }
};

const Token = GenerateTokenEnumType(Vm);

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
            _ = @call(empty, @field(Vm, "op_" ++ @tagName(enumValue)), .{vm});
        }
    }
}

fn shellLoop(stdin: std.fs.File.Reader, stdout: std.fs.File.Writer) !void {
    const max_input = 1024;
    var input_buffer: [max_input]u8 = undefined;
    var vm = Vm{};

    while (true) {

```

 Prompt

```zig

        try stdout.print("> ", .{});

```

 Read STDIN into buffer

```zig

        var input_str = (try stdin.readUntilDelimiterOrEof(input_buffer[0..], '\n')) orelse {
```

 No input, probably CTRL-d (EOF). Print a newline and exit!

```zig

            try stdout.print("\n", .{});
            return;
        };

```

 Don't do anything for zero-length input (user just hit Enter).

```zig

        if (input_str.len == 0) continue;

```

 Split by a single space. The returned SplitIterator must be var because
 it has mutable internal state.

```zig

        var words = std.mem.tokenize(u8, input_str, " ");

        while (words.next()) |word| {
            const token = findToken(word) orelse Token.notFound;
            execToken(&vm, token);
        }
        std.log.info("{}", .{vm.state});
    }
}

pub fn main() !u8 {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    try stdout.print("*** Hello, I am a real shell! ***\n", .{});

    try shellLoop(stdin, stdout);

    return 0; // We either crash or we are fine.
}

fn GenerateTokenEnumType(comptime T: type) type {
    const fieldInfos = std.meta.declarations(T);
    var enumDecls: [fieldInfos.len]std.builtin.TypeInfo.EnumField = undefined;
    var decls = [_]std.builtin.TypeInfo.Declaration{};
    inline for (fieldInfos) |field, i| {
        const name = field.name;
        if (name[0] == 'o' and name[1] == 'p') {
            enumDecls[i] = .{ .name = field.name[3..], .value = i };
        }
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
```
