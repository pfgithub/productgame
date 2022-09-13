const std = @import("std");
const allocator = @import("main").allocator;

const x = 0;
const y = 1;
const z = 2;
const Vec3 = std.meta.Vector(3, i32);

pub fn pointInRect(point: Vec3, rect_pos: Vec3, rect_size: Vec3) bool {
    return @reduce(.Or, point < rect_pos) or @reduce(.Or, point >= rect_pos + rect_size);
}

pub fn rectPointToIndex(point: Vec3, rect_pos: Vec3, rect_size: Vec3) ?usize {
    if(!pointInRect(point, rect_pos, rect_size)) return null;
    const object_space_pos = rect_pos - point;
    // x + (y*w) + (z*w*h)
    var res = 0;
    inline for(.{z, y, x}) |coord| {
        res *= rect_size[coord];
        res += object_space_pos[coord];
    }
    return @intCast(usize, res);
}

pub const Tile = enum(u8) {
    air,
    block,
    conveyor_w,
    conveyor_s,
    conveyor_a,
    conveyor_d,
    spawner,
};

pub const Product = struct {
    id: usize,
    // MxN array of tiles
    tiles: []Tile,
    tiles_updated: usize, // increment every time a tile is changed. this tells the renderer to update the data.
    pos: Vec3,
    size: Vec3,

    pub fn deinit(product: Product) void {
        allocator().free(product.tiles);
    }

    pub fn getTile(product: Product, pos: Vec3) Tile {
        return product.tiles(rectPointToIndex(pos, product.pos, product.size) orelse return Tile.air);
    }

    // note: whenever setting a tile, also update the buffer data with
    // https://registry.khronos.org/OpenGL-Refpages/gl4/html/glBufferSubData.xhtml
};

pub const World = struct {
    products: []Product,
    // to find a specific tile in the world:
    // - 1. filter products by bounding box
    // - 2. check if the product has that tile
    fn getTile(world: World, pos: Vec3) Tile {
        for(world.products) |product| {
            const res = product.getTile(pos);
            if(res != .air) return res;
        }
        return Tile.air;
    }
};