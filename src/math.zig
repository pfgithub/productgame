const std = @import("std");
const log = std.log.scoped(.math);

pub const SwizzleChars = struct {
    pub const x = 0;
    pub const y = 1;
    pub const z = 2;
    pub const w = 3;
};
pub usingnamespace SwizzleChars;
const x = SwizzleChars.x;
const y = SwizzleChars.y;
const z = SwizzleChars.z;
const w = SwizzleChars.w;


pub const Vec = std.meta.Vector;

pub const Vec2i = Vec(2, i32);
pub const Vec3i = Vec(3, i32);
pub const Vec2f = Vec(2, f64);
pub const Vec3f = Vec(3, f64);

pub fn EcastRet(comptime Target: type, comptime Value: type) type {
    const v_ty = @typeInfo(Value);
    return switch(v_ty) {
        .Int, .Float => return Target,
        .Vector => |vec| {
            return Vec(vec.len, Target);
        },
        else => @compileError("cannot ecast this type"),
    };
}
pub fn ecast(comptime Target: type, value: anytype) EcastRet(Target, @TypeOf(value)) {
    const v_ty = @typeInfo(@TypeOf(value));
    return switch(v_ty) {
        .Int, .Float => std.math.lossyCast(Target, value),
        .Vector => |vec| {
            var res: EcastRet(Target, @TypeOf(value)) = undefined;
            inline for(comptime range(vec.len)) |_, i| {
                res[i] = ecast(Target, value[i]);
            }
            return res;
        },
        else => @compileError("cannot ecast this type"),
    };
}
pub fn SwizzleRet(comptime ValTy: type, comptime tag: EnumLiteral) type {
    const nvec_len = @tagName(tag).len;
    const child_ty = @typeInfo(ValTy).Vector.child;
    if(nvec_len == 1) return child_ty;
    return Vec(nvec_len, child_ty);
}
pub fn swizzle(value: anytype, comptime tag: EnumLiteral) SwizzleRet(@TypeOf(value), tag) {
    // consider using the @shuffle intrinsic here
    // @shuffle(ty, vec, undefined, mask) where mask = vec(tag.len, i32){ swizzlechar }
    // we could make the second vec have some common values eg 0, 1, -1, …
    if(@tagName(tag).len == 1) {
        return value[comptime @field(SwizzleChars, @tagName(tag))];
    }
    var res: SwizzleRet(@TypeOf(value), tag) = undefined;
    inline for(@tagName(tag)) |char, i| {
        res[i] = value[comptime @field(SwizzleChars, &[_]u8{char})];
    }
    return res;
}
// join(f64, .{0, 0, 0})
// join(f64, .{vec2f(), 0})
pub fn JoinResultType(comptime Type: type, comptime Value: anytype) type {
    var total: usize = 0;
    for(std.meta.fields(Value)) |field| {
        const tyi = @typeInfo(field.field_type);
        if(tyi == .Vector) {
            total += tyi.Vector.len;
        }else{
            total += 1;
        }
    }
    return Vec(total, Type);
}
pub fn join(comptime Type: type, value: anytype) JoinResultType(Type, @TypeOf(value)) {
    var res: JoinResultType(Type, @TypeOf(value)) = undefined;
    comptime var i: usize = 0;
    inline for(value) |v| {
        const tyi = @typeInfo(@TypeOf(v));
        if(tyi == .Vector) {
            comptime var vec_i: usize = 0;
            inline while(vec_i < tyi.Vector.len) : (vec_i += 1) {
                res[i] = v[vec_i];
                i += 1;
            }
        }else{
            res[i] = v;
            i += 1;
        }
    }
    return res;
}

pub const EnumLiteral = @Type(.EnumLiteral);

pub fn range(len: usize) []const void {
    // return (&[_]void{})[0..len];
    return @as([*]const void, &[_]void{})[0..len];
}
