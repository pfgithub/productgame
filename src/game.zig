const std = @import("std");
const allocator = @import("main.zig").allocator;
const log = std.log.scoped(.game);

pub const x = 0;
pub const y = 1;
pub const z = 2;
pub const Vec2i = std.meta.Vector(2, i32);
pub const Vec3i = std.meta.Vector(3, i32);
pub const Vec2f = std.meta.Vector(2, f64);
pub const Vec3f = std.meta.Vector(3, f64);

pub fn pointInRect(point: Vec3i, rect_pos: Vec3i, rect_size: Vec3i) bool {
    return !(@reduce(.Or, point < rect_pos) or @reduce(.Or, point >= rect_pos + rect_size));
}

pub fn rectPointToIndex(point: Vec3i, rect_pos: Vec3i, rect_size: Vec3i) ?usize {
    if(!pointInRect(point, rect_pos, rect_size)) return null;
    const object_space_pos = point - rect_pos;
    // x + (y*w) + (z*w*h)
    var res: i32 = 0;
    inline for(.{z, y, x}) |coord| {
        res *= rect_size[coord];
        res += object_space_pos[coord];
    }
    return @intCast(usize, res);
}

pub const TileID = enum(u8) {
    air,
    lab_tile,
    conveyor,
    spawner,
    block,
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

pub fn conveyorDir(conveyor: Tile) Vec2i {
    return switch(conveyor.data_1) {
        // 0 1 2 3 w a s d
        0 => Vec2i{0, -1},
        1 => Vec2i{-1, 0},
        2 => Vec2i{1, 0},
        3 => Vec2i{0, 1},
        else => Vec2i{0, 0},
    };
}

pub const Product = struct {
    id: ProductID,
    // MxN array of tiles
    tiles: []Tile,
    tiles_updated: usize, // increment every time a tile is changed. this tells the renderer to update the data.
    pos: Vec3i,
    size: Vec3i,
    last_moved: usize = 0,
    moved_from: Vec3i = Vec3i{0, 0, 0},
    fixed: bool = false,

    pub fn deinit(product: *Product) void {
        allocator().free(product.tiles);
    }

    pub fn getTile(product: Product, pos: Vec3i) Tile {
        return product.tiles[rectPointToIndex(pos, product.pos, product.size) orelse return Tile.Air];
    }

    // note: whenever setting a tile, also update the buffer data with
    // https://registry.khronos.org/OpenGL-Refpages/gl4/html/glBufferSubData.xhtml
};

const PosIter = struct {
    pos: Vec3i,
    size: Vec3i,
    next_pos: Vec3i,
    pub fn start(pos: Vec3i, size: Vec3i) PosIter {
        return .{
            .pos = pos,
            .size = size,
            .next_pos = pos,
        };
    }
    pub fn next(iter: *PosIter) ?Vec3i {
        if(iter.next_pos[z] - iter.pos[z] >= iter.size[z]) return null;
        const res = iter.next_pos;

        iter.next_pos[x] += 1;
        if(iter.next_pos[x] - iter.pos[x] >= iter.size[x]) {
            iter.next_pos[y] += 1;
            iter.next_pos[x] = iter.pos[x];
        }
        if(iter.next_pos[y] - iter.pos[y] >= iter.size[y]) {
            iter.next_pos[z] += 1;
            iter.next_pos[y] = iter.pos[y];
        }

        return res;
    }
};

pub const World = struct {
    products: std.ArrayList(Product),
    physics_time: usize = 1,
    next_product_id: usize = 1,

    pub fn nextProductId(world: *World) ProductID {
        defer world.next_product_id += 1;
        return @intToEnum(ProductID, world.next_product_id);
    }

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
    fn getTile(world: World, pos: Vec3i) ?struct{product: *Product, tile: Tile} {
        for(world.products.items) |*product| {
            const res = product.getTile(pos);
            if(res.id != .air) return .{.product = product, .tile = res};
        }
        return null;
    }

    pub fn physicsStep(world: *World) void {
        world.physics_time += 1;
        // 1. conveyors move
        // - an object can only move in one direction at once
        //   - we could do something fun like if an object is pushed in two directions
        //      at once, it locks up both conveyor belts

        // ok idk let's just start. figure out edge cases later. that way we can start on ui and stuff

        for(world.products.items) |*product| {
            var iter_pos = PosIter.start(product.pos, product.size);
            // hmm. this is having the conveyor move the object but it would probably be better for
            // the object to move itself
            while(iter_pos.next()) |target_pos| {
                const tile = product.getTile(target_pos);
                if(tile.id == .conveyor) {
                    const tile_above = world.getTile(target_pos + Vec3i{0, 0, 1}) orelse continue;
                    if(tile_above.product == product) continue;
                    if(tile_above.product.last_moved == world.physics_time) continue;
                    const dir = conveyorDir(tile);

                    _ = world.pushProduct(tile_above.product, Vec3i{dir[x], dir[y], 0});
                }
            }

            if(product.last_moved == world.physics_time) continue;
            _ = world.pushProduct(product, Vec3i{0, 0, -1});
        }
    }

    pub fn validatePushProduct(
        world: *World,
        product: *Product,
        direction: Vec3i,
        pushable_products: *std.ArrayList(*Product),
    ) bool {
        if(product.fixed) return false;
        for(pushable_products.items) |psh_p| {
            if(product == psh_p) return true;
        }
        pushable_products.append(product) catch @panic("oom"); // we don't know if it's pushable
        // yet but until we have proven it isn't, we say it is

        var iter_pos = PosIter.start(product.pos, product.size);
        while(iter_pos.next()) |target_pos| {
            const product_tile = product.getTile(target_pos);
            if(product_tile.id == .air) continue;
            const tile = world.getTile(target_pos + direction) orelse continue;
            if(tile.product.id == product.id) continue;
            if(world.validatePushProduct(tile.product, direction, pushable_products)) continue;
            return false;
        }

        return true;
    }

    pub fn pushProduct(world: *World, product: *Product, direction: Vec3i) bool {
        var pushable_products = std.ArrayList(*Product).init(allocator());
        defer pushable_products.deinit();
        if(!world.validatePushProduct(product, direction, &pushable_products)) {
            return false; // push failed
        }

        for(pushable_products.items) |psh_p| {
            psh_p.moved_from = psh_p.pos;
            psh_p.last_moved = world.physics_time;
            psh_p.pos += direction;
        }

        return true;
    }
};
