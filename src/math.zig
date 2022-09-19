const std = @import("std");
const log = std.log.scoped(.math);

pub const x = 0;
pub const y = 1;
pub const z = 2;
pub const w = 3;

pub const Vec = std.meta.Vector;

pub const Vec2i = Vec(2, i32);
pub const Vec3i = Vec(3, i32);
pub const Vec2f = Vec(2, f64);
pub const Vec3f = Vec(3, f64);