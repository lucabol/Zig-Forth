const std = @import("std");

const Vm = struct {
    state: i32,

    fn op_double(this: Vm) Vm { return Vm { .state = this.state * 2 };}
    fn op_plus1 (this: Vm) Vm { return Vm { .state = this.state + 1 };}
};

fn DeclEnum(comptime T: type) type {
    const fieldInfos = std.meta.declarations(T);
    var enumDecls: [fieldInfos.len]std.builtin.TypeInfo.EnumField = undefined;
    var decls = [_]std.builtin.TypeInfo.Declaration{};
    inline for (fieldInfos) |field, i| {
        const name = field.name;
        if(name[0] == 'o' and name[1] == 'p') {
            enumDecls[i] = .{ .name = field.name, .value = i };
        }
    }
    return @Type(.{
        .Enum              = .{
            .layout        = .Auto,
            .tag_type      = u8,
            .fields        = &enumDecls,
            .decls         = &decls,
            .is_exhaustive = true,
        },
    });
}

const Token = DeclEnum(Vm);

fn ReadByteToken() u8 {
    return 1; 
}
pub fn main() anyerror!void {
    const byte = ReadByteToken();

    inline for(@typeInfo(Token).Enum.fields) |token| {
        const declInfo = std.meta.declarationInfo(Vm, token.name);
        if (token.value == byte) {
            @call(.{}, declInfo, .{});
            std.log.info("{s}", .{token.name});
        }
    }
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
