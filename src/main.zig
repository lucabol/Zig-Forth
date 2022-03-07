// While writing my C# Forth, I grew unhappy about the conceptual repetition in the code.
// To add a new Forth word, you have to add a new value to the enumerator that represents the opcode,
// add a new member to a hashtable that maps it to a string (what the user types) and finally implement the action
// for the word. See [here.](https://www.lucabol.com/posts/2022-03-07-implementing-forth-dotnet/#interpreting-words)
//
// Granted, by using a `struct`, I could have kept these items geographically closer, but the repetition is there.
// Using reflection, I could have removed it, but then performance would suck in the inner loop
// of my interpreter.
//
// My familiarity with the `Zig` language made me realize that I could remove the redundancy by using
// zig's `comptime`, without any loss in performance. This post describes a prototype of that.
//
// The idea is to have functions on my main `struct` in the form `op_WORDNAME`. At compile time, I
// generate the enumerator with all the opcodes and the series of conditional statements to call the right
// function `op_WORDNAME` when the user types `WORDNAME`. By making the functions `inline`, I don't even pay
// the price of a function call. BTW: Zig gives a compile-time error if it can't inline.
//
// In the `Vm` code below, if you want to support a new word, you add a new function.
// The rest of the code is unchanged.
const std = @import("std");

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

// This is the shell main loop. It is pretty standard stuff until you get to the innermost while loop,
// marked with (*). Even if it looks like the code is calling two functions (`findToken` and `execToken`),
// it isn't. The compiler replaces these two function calls with a series of `if` statements to match
// a string with the corresponding opcode and to find the correct function to call.
//
// Even the enumerator `Token` is not defined anywhere in the code. It is generated automatically at compile
// time and contains one value for each `op_XXX` function defined on `Vm`. Even if I have not defined it,
// I can still access the values normally (i.e., see `Token.ntFound` below).
fn shellLoop(stdin: std.fs.File.Reader, stdout: std.fs.File.Writer) !void {
    const max_input = 1024;
    var input_buffer: [max_input]u8 = undefined;
    var vm = Vm{};

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

// So, how do we do it? Let's start with `findToken`. The code is relatively simple because you are not
// writing a 'macro'. You are just writing normal Zig code. For .NET programmers, this is like having
// `System.Reflection` and `System.Reflection.Emit` available at compile time.
//
// You could do something similar
// with [C# source generators](https://docs.microsoft.com/en-us/dotnet/csharp/roslyn-sdk/source-generators-overview),
// but you would need to operate on a rather complex 'AST' and generate code using string concatenation. It would
// probably be dozens of lines of very intricated code. Here, it is three simple lines.
//
// An `inline for` tells Zig to unroll the loop. The compiler iterates overa all the field of the `Enum`
// and generates a series of `if` statements that return the value of the `Enum` that matches the given string
// (what the user typed).
inline fn findToken(word: []const u8) ?Token {
    inline for (@typeInfo(Token).Enum.fields) |enField| {
        if (std.mem.eql(u8, enField.name, word))
            return @field(Token, enField.name);
    }
    return null;
}

// `Token` execution is similar. Again we unroll the loop at compile time, generating a series of `if`
// statements that execute the `Vm` function corresponding to the given `Token`.
inline fn execToken(vm: *Vm, tok: Token) void {
    inline for (@typeInfo(Token).Enum.fields) |enField| {
        const enumValue = @field(Token, enField.name);
        if (enumValue == tok) {
            const empty = .{};
            _ = @call(empty, @field(Vm, "op_" ++ @tagName(enumValue)), .{vm});
        }
    }
}

// We generate the `Token` enumerator by iterating over all the declarations on the `Vm` struct and
// generating a set of declarations that are then use to compile time construct the correct `Enum` using
// the `@Type` builtin function.
const Token = GenerateTokenEnumType(Vm);

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

// Ok, but does it really work? Well, you can run it with `zig build run`, but it is really inlining
// correctly? Well, the assembly language says yes. No calls to external functions in the main loop.
//
// ```asm
//            const token = findToken(word) orelse Token.notFound;
//  2310db:       f6 85 a1 fa ff ff 01    testb  $0x1,-0x55f(%rbp)
//  2310e2:       75 09                   jne    2310ed <shellLoop+0x38d>
//  2310e4:       c6 85 9f fa ff ff 02    movb   $0x2,-0x561(%rbp)
//  2310eb:       eb 0c                   jmp    2310f9 <shellLoop+0x399>
//  2310ed:       8a 85 a0 fa ff ff       mov    -0x560(%rbp),%al
//  2310f3:       88 85 9f fa ff ff       mov    %al,-0x561(%rbp)
// home/lucabol/dev/zig-forth/src/main.zig:65
//            execToken(&vm, token);
//  2310f9:       8a 85 9f fa ff ff       mov    -0x561(%rbp),%al
//  2310ff:       48 8d 8d 58 fb ff ff    lea    -0x4a8(%rbp),%rcx
//  231106:       48 89 4d d8             mov    %rcx,-0x28(%rbp)
//  23110a:       88 45 d7                mov    %al,-0x29(%rbp)
// execToken():
// home/lucabol/dev/zig-forth/src/main.zig:32
//        if (enumValue == tok) {
//  23110d:       31 c0                   xor    %eax,%eax
//  23110f:       3a 45 d7                cmp    -0x29(%rbp),%al
//  231112:       75 50                   jne    231164 <shellLoop+0x404>
// home/lucabol/dev/zig-forth/src/main.zig:34
//            _ = @call(empty, @field(Vm, "op_" ++ @tagName(enumValue)), .{vm});
//  231114:       48 8b 45 d8             mov    -0x28(%rbp),%rax
//  231118:       48 89 45 e0             mov    %rax,-0x20(%rbp)
// Vm.op_double():
// home/lucabol/dev/zig-forth/src/main.zig:7
//        this.state = this.state * 2;
//  23111c:       48 8b 45 e0             mov    -0x20(%rbp),%rax
//  231120:       48 89 85 58 fa ff ff    mov    %rax,-0x5a8(%rbp)
//  231127:       48 8b 4d e0             mov    -0x20(%rbp),%rcx
//  23112b:       b8 02 00 00 00          mov    $0x2,%eax
//  231130:       0f af 01                imul   (%rcx),%eax
//  231133:       89 85 60 fa ff ff       mov    %eax,-0x5a0(%rbp)
//  231139:       0f 90 c0                seto   %al
//  23113c:       70 02                   jo     231140 <shellLoop+0x3e0>
//  23113e:       eb 13                   jmp    231153 <shellLoop+0x3f3>
//  231140:       48 bf 68 1f 20 00 00 00 00 00   movabs $0x201f68,%rdi
//  23114a:       31 c0                   xor    %eax,%eax
//  23114c:       89 c6                   mov    %eax,%esi
//  23114e:       e8 fd 32 fd ff          callq  204450 <std.builtin.default_panic>
//  231153:       48 8b 85 58 fa ff ff    mov    -0x5a8(%rbp),%rax
//  23115a:       8b 8d 60 fa ff ff       mov    -0x5a0(%rbp),%ecx
//  231160:       89 08                   mov    %ecx,(%rax)
// execToken():
// home/lucabol/dev/zig-forth/src/main.zig:32
//        if (enumValue == tok) {
//  231162:       eb 02                   jmp    231166 <shellLoop+0x406>
//  231164:       eb 00                   jmp    231166 <shellLoop+0x406>
//  231166:       b0 01                   mov    $0x1,%al
//  231168:       3a 45 d7                cmp    -0x29(%rbp),%al
//  23116b:       75 4c                   jne    2311b9 <shellLoop+0x459>
// home/lucabol/dev/zig-forth/src/main.zig:34
//            _ = @call(empty, @field(Vm, "op_" ++ @tagName(enumValue)), .{vm});
//  23116d:       48 8b 45 d8             mov    -0x28(%rbp),%rax
//  231171:       48 89 45 e8             mov    %rax,-0x18(%rbp)
// Vm.op_plus1():
// home/lucabol/dev/zig-forth/src/main.zig:10
//        this.state = this.state + 1;
//  231175:       48 8b 45 e8             mov    -0x18(%rbp),%rax
//  231179:       48 89 85 48 fa ff ff    mov    %rax,-0x5b8(%rbp)
//  231180:       48 8b 45 e8             mov    -0x18(%rbp),%rax
//  231184:       8b 00                   mov    (%rax),%eax
//  231186:       ff c0                   inc    %eax
//  231188:       89 85 54 fa ff ff       mov    %eax,-0x5ac(%rbp)
//  23118e:       0f 90 c0                seto   %al
// ```
//
// Also, more directly, see below:
//
// ```
//             return @field(Token, enField.name);
//  230ff0:       c6 85 a1 fa ff ff 01    movb   $0x1,-0x55f(%rbp)
// inlined by /home/lucabol/dev/zig-forth/src/main.zig:64 (shellLoop)
//  230ff7:       c6 85 a0 fa ff ff 00    movb   $0x0,-0x560(%rbp)
// inlined by /home/lucabol/dev/zig-forth/src/main.zig:64 (shellLoop)
//  230ffe:       e9 d8 00 00 00          jmpq   2310db <shellLoop+0x37b>
// home/lucabol/dev/zig-forth/src/main.zig:24
// inlined by /home/lucabol/dev/zig-forth/src/main.zig:64 (shellLoop)
//        if (std.mem.eql(u8, enField.name, word))
//  231003:       48 8b 85 a8 fa ff ff    mov    -0x558(%rbp),%rax
// inlined by /home/lucabol/dev/zig-forth/src/main.zig:64 (shellLoop)
//  23100a:       48 89 45 b0             mov    %rax,-0x50(%rbp)
// inlined by /home/lucabol/dev/zig-forth/src/main.zig:64 (shellLoop)
//  23100e:       48 8b 85 b0 fa ff ff    mov    -0x550(%rbp),%rax
// inlined by /home/lucabol/dev/zig-forth/src/main.zig:64 (shellLoop)
//  231015:       48 89 45 b8             mov    %rax,-0x48(%rbp)
// inlined by /home/lucabol/dev/zig-forth/src/main.zig:64 (shellLoop)
//  231019:       48 bf e0 2a 20 00 00 00 00 00   movabs $0x202ae0,%rdi
// inlined by /home/lucabol/dev/zig-forth/src/main.zig:64 (shellLoop)
//  231023:       48 8d b5 a8 fa ff ff    lea    -0x558(%rbp),%rsi
// inlined by /home/lucabol/dev/zig-forth/src/main.zig:64 (shellLoop)
//  23102a:       e8 61 ac fd ff          callq  20bc90 <std.mem.eql>
// inlined by /home/lucabol/dev/zig-forth/src/main.zig:64 (shellLoop)
//  23102f:       a8 01                   test   $0x1,%al
// inlined by /home/lucabol/dev/zig-forth/src/main.zig:64 (shellLoop)
//  231031:       75 02                   jne    231035 <shellLoop+0x2d5>
// inlined by /home/lucabol/dev/zig-forth/src/main.zig:64 (shellLoop)
//  231033:       eb 13                   jmp    231048 <shellLoop+0x2e8>
// home/lucabol/dev/zig-forth/src/main.zig:25
// inlined by /home/lucabol/dev/zig-forth/src/main.zig:64 (shellLoop)
//            return @field(Token, enField.name);
// ```
//
// And the driver is obvious.
pub fn main() !u8 {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    try stdout.print("*** Hello, I am a Forth shell! ***\n", .{});

    try shellLoop(stdin, stdout);

    return 0; // We either crash or we are fine.
}
