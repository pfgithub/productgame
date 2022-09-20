const std = @import("std");
const allocator = @import("main.zig").allocator;
const math = @import("math.zig");
const log = std.log.scoped(.game);

const x = math.x;
const y = math.y;
const z = math.z;
const Vec2i = math.Vec2i;
const Vec3i = math.Vec3i;
const Vec2f = math.Vec2f;
const Vec3f = math.Vec3f;

pub fn pointInRect(point: Vec3i, rect_pos: Vec3i, rect_size: Vec3i) bool {
    return !(@reduce(.Or, point < rect_pos) or @reduce(.Or, point >= rect_pos + rect_size));
}

pub fn rectPointToIndex(point: Vec3i, rect_size: Vec3i) usize {
    if(!pointInRect(point, .{0, 0, 0}, rect_size)) unreachable;

    const object_space_pos = point;
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

// note: product max size is 255 on any axis = 16581375 maximum tiles in a product
// for larger products:
// - display an error "the objects cannot be welded because it is too big"
// for the map:
// - chunk it to be 255x255x2 or something
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

    pub fn getTile(product: Product, offset: Vec3i) Tile {
        return product.tiles[rectPointToIndex(offset, product.size)];
    }
    pub fn setTile(product: Product, offset: Vec3i, tile: Tile) void {
        product.tiles[rectPointToIndex(offset, product.size)] = tile;
    }

    pub fn containsPoint(product: Product, point: Vec3i) ?Vec3i {
        if(pointInRect(point, product.pos, product.size)) {
            return point - product.pos;
        }
        return null;
    }
    pub fn toWorldSpace(product: Product, point: Vec3i) Vec3i {
        return product.pos + math.ecast(i32, point);
    }

    // note: whenever setting a tile, also update the buffer data with
    // https://registry.khronos.org/OpenGL-Refpages/gl4/html/glBufferSubData.xhtml
};

const PosIter = struct {
    size: Vec3i,
    next_pos: Vec3i,
    pub fn start(size: Vec3i) PosIter {
        return .{
            .size = size,
            .next_pos = Vec3i{0, 0, 0},
        };
    }
    pub fn next(iter: *PosIter) ?Vec3i {
        if(iter.next_pos[z] >= iter.size[z]) return null;
        const res = iter.next_pos;

        iter.next_pos[x] += 1;
        if(iter.next_pos[x] >= iter.size[x]) {
            iter.next_pos[y] += 1;
            iter.next_pos[x] = 0;
        }
        if(iter.next_pos[y] >= iter.size[y]) {
            iter.next_pos[z] += 1;
            iter.next_pos[y] = 0;
        }

        return res;
    }
};

pub const World = struct {
    // vv if this ever gets too much to loop over:
    //   - https://gamedev.stackexchange.com/questions/21747/how-to-continuously-find-all-entities-within-a-radius-efficiently
    // I suspect it will be fine though and we'll run into issues rendering lots of products long before
    // we run into issues querying products in the physics function. Maybe not depending on how large products
    // get though.
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
    fn getTile(world: World, pos: Vec3i) ?struct{product: *Product, tile: Tile, offset: Vec3i} {
        for(world.products.items) |*product| {
            if(product.containsPoint(pos)) |ps_point| {
                const res = product.getTile(ps_point);
                if(res.id != .air) return .{.product = product, .tile = res, .offset = ps_point};
            }
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

        var i: usize = 0;
        while(i < world.products.items.len) : (i += 1) {
            var product = &world.products.items[i];
            var iter_pos = PosIter.start(product.size);
            // hmm. this is having the conveyor move the object but it would probably be better for
            // the object to move itself
            while(iter_pos.next()) |target_ps_pos| {
                const target_ws_pos = product.toWorldSpace(target_ps_pos);
                const tile = product.getTile(target_ps_pos);
                if(tile.id == .spawner) {
                    const tile_above = world.getTile(target_ws_pos + Vec3i{0, 0, 1});
                    if(tile_above == null) {
                        // summon product
                        const t_block = Tile{.id = .block};
                        const newproduct_tiles = allocator().dupe(Tile, &[_]Tile{
                            t_block,
                        }) catch @panic("oom");
                        const newproduct = Product{
                            .id = world.nextProductId(),
                            // MxN array of tiles
                            .tiles = newproduct_tiles,
                            .tiles_updated = 1,
                            .pos = target_ws_pos + Vec3i{0, 0, 1},
                            .size = Vec3i{1, 1, 1},
                        };
                        world.products.append(newproduct) catch @panic("oom");
                        product = &world.products.items[i];
                    }
                }
                if(tile.id == .conveyor or tile.id == .spawner) {
                    const tile_above = world.getTile(target_ws_pos + Vec3i{0, 0, 1}) orelse continue;
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

        var iter_pos = PosIter.start(product.size);
        while(iter_pos.next()) |target_ps_pos| {
            const target_ws_pos = product.toWorldSpace(target_ps_pos);
            const product_tile = product.getTile(target_ps_pos);
            if(product_tile.id == .air) continue;
            const tile = world.getTile(target_ws_pos + direction) orelse continue;
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

    pub fn placeTile(world: *World, pos: Vec3i, new_tile: Tile) !void {
        if(new_tile.id == .air) @panic("TODO deleteTile");
        const current_block = world.getTile(pos);
        if(current_block) |cb| {
            cb.product.setTile(cb.offset, new_tile);
            std.log.info("✓ set", .{});
        }else{
            std.log.info("TODO set new tile", .{});
        }
    }
};
