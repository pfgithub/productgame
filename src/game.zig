const std = @import("std");
const allocator = @import("main.zig").allocator;
const log = std.log.scoped(.game);

pub const x = 0;
pub const y = 1;
pub const z = 2;
pub const Vec2 = std.meta.Vector(2, i32);
pub const Vec3 = std.meta.Vector(3, i32);
pub const Vec2f = std.meta.Vector(2, f32);
pub const Vec3f = std.meta.Vector(3, f32);

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

pub const TileID = enum(u8) {
    air,
    block,
    conveyor,
    spawner,
};
pub const Tile = struct {
    id: TileID,
    data_1: u8 = 0,
    data_2: u8 = 0,
    data_3: u8 = 0,
    // for more data, use a hashmap indexed with the object position or something

    pub const Air = Tile{.id = .air};
};

pub const ProductID = enum(usize) {_};

pub const Product = struct {
    id: ProductID,
    // MxN array of tiles
    tiles: []Tile,
    tiles_updated: usize, // increment every time a tile is changed. this tells the renderer to update the data.
    pos: Vec3,
    size: Vec3,

    pub fn deinit(product: *Product) void {
        allocator().free(product.tiles);
    }

    pub fn getTile(product: Product, pos: Vec3) Tile {
        return product.tiles(rectPointToIndex(pos, product.pos, product.size) orelse return Tile.Air);
    }

    // note: whenever setting a tile, also update the buffer data with
    // https://registry.khronos.org/OpenGL-Refpages/gl4/html/glBufferSubData.xhtml
};

pub const World = struct {
    products: std.ArrayList(Product),

    pub fn init() !World {
        const products = std.ArrayList(Product).init(allocator());

        return .{
            .products = products,
        };
    }
    pub fn deinit(world: *World) void {
        for(world.products.items) |*item| {
            item.deinit();
        }
        world.products.deinit();
    }

    // to find a specific tile in the world:
    // - 1. filter products by bounding box
    // - 2. check if the product has that tile
    fn getTile(world: World, pos: Vec3) struct{product: ?*Product, tile: Tile} {
        for(world.products.items) |*product| {
            const res = product.getTile(pos);
            if(res != .air) return .{.product = product, .tile = res};
        }
        return .{.product = null, .tile = Tile.Air};
    }

    fn physicsStep(world: *World) void {
        // 1. conveyors move
        // - an object can only move in one direction at once
        //   - we could do something fun like if an object is pushed in two directions
        //      at once, it locks up both conveyor belts

        // ok idk let's just start. figure out edge cases later. that way we can start on ui and stuff

        for(world.products) |*product| {
            var iter_pos = product.pos;
            while(iter_pos[z] < product.size[z]) : ({
                iter_pos[x] += 1;
                if(iter_pos[x] > product.size[x]) {
                    iter_pos[y] += 1;
                    iter_pos[x] = product.pos[x];
                }
                if(iter_pos[y] > product.size[y]) {
                    iter_pos[z] += 1;
                    iter_pos[y] = product.pos[y];
                }
            }) {
                const tile = product.getTile(iter_pos);
                if(tile.id == .conveyor) {
                    // check if there's an object above
                    // push the object if possible
                }
            }
        }
    }
};
