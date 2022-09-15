const std = @import("std");
const sdl = @import("sdl.zig");
const game = @import("game.zig");
const render = @import("render.zig");
const plat = @import("platform.zig");
const c = sdl.c;
const log = std.log.scoped(.main);

// https://www.khronos.org/opengl/wiki/Buffer_Texture

var global_allocator: ?std.mem.Allocator = null;
pub fn allocator() std.mem.Allocator {
    return global_allocator.?;
}

pub fn main() !void {
    main2() catch |e| switch(e) {
        error.ShaderCompilationFailed => std.os.exit(1),
        else => return e,
    };
}

pub fn main2() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if(gpa.deinit()) unreachable;
    global_allocator = gpa.allocator();

    var platform = try plat.Platform.init();

    var world = try game.World.init();
    defer world.deinit();

    const t_block = game.Tile{.id = .block};
    const t_conveyor_w = game.Tile{.id = .conveyor, .data_1 = 0};
    const t_conveyor_a = game.Tile{.id = .conveyor, .data_1 = 1};
    // const t_conveyor_s = game.Tile{.id = .conveyor, .data_1 = 2};
    // const t_conveyor_d = game.Tile{.id = .conveyor, .data_1 = 3};
    const t_air = game.Tile{.id = .air};
    {
        const newproduct_tiles = try allocator().dupe(game.Tile, &[_]game.Tile{
            t_block, t_block, t_block, t_block, t_block, t_block, t_block, t_block, t_block, t_block,
            t_block, t_conveyor_a, t_conveyor_a, t_conveyor_a, t_block, t_block, t_block, t_block, t_block, t_block,
            t_block, t_block, t_block, t_conveyor_w, t_block, t_block, t_block, t_block, t_block, t_block,
            t_block, t_block, t_block, t_conveyor_w, t_block, t_block, t_block, t_block, t_block, t_block,
            t_block, t_block, t_block, t_conveyor_w, t_block, t_block, t_block, t_block, t_block, t_block,
            t_block, t_block, t_block, t_conveyor_w, t_block, t_block, t_block, t_block, t_block, t_block,
            t_block, t_block, t_block, t_block, t_block, t_block, t_block, t_block, t_block, t_block,
            t_block, t_block, t_block, t_block, t_block, t_block, t_block, t_block, t_block, t_block,
            t_block, t_block, t_block, t_block, t_block, t_block, t_block, t_block, t_block, t_block,
            t_block, t_block, t_block, t_block, t_block, t_block, t_block, t_block, t_block, t_block,
        });
        const newproduct = game.Product{
            .id = @intToEnum(game.ProductID, 1),
            // MxN array of tiles
            .tiles = newproduct_tiles,
            .tiles_updated = 1,
            .pos = game.Vec3{5, 5, 0},
            .size = game.Vec3{10, 10, 1},
        };
        try world.products.append(newproduct);
    }
    {
        const newproduct_tiles = try allocator().dupe(game.Tile, &[_]game.Tile{
            t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_block, t_block, t_air,
            t_air, t_air, t_block, t_block, t_air,
            t_air, t_air, t_block, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air,
        });
        const newproduct = game.Product{
            .id = @intToEnum(game.ProductID, 2),
            // MxN array of tiles
            .tiles = newproduct_tiles,
            .tiles_updated = 1,
            .pos = game.Vec3{6, 7, 1},
            .size = game.Vec3{5, 5, 1},
        };
        try world.products.append(newproduct);
    }

    var renderer = try render.Renderer.init(&platform, &world);

    var fullscreen = false;

    app: while(true) {
        try sdl.glCheckError();

        while(platform.pollEvent()) |event| {
            if(event.type == c.SDL_KEYDOWN) {
                switch(event.key.keysym.sym) {
                    c.SDLK_ESCAPE => {},
                    'f' => {
                        fullscreen =! fullscreen;
                        platform.setFullscreen(fullscreen) catch {
                            fullscreen =! fullscreen;
                        };
                    },
                    'r' => {
                        renderer.recompileShaders() catch |e| {
                            log.err("Failed to recompile shaders: {}", .{e});
                        };
                    },
                    else => {},
                }
            }else if(event.type == c.SDL_QUIT) {
                break :app;
            }
        }

        try renderer.renderFrame();

        platform.present();
    }
}
