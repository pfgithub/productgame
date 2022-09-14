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

    {
        const newproduct_tiles = try allocator().dupe(game.Tile, &[_]game.Tile{
            .block, .block, .block, .block, .block, .block, .block, .block, .block, .block,
            .block, .conveyor_a, .conveyor_a, .conveyor_a, .block, .block, .block, .block, .block, .block,
            .block, .block, .block, .conveyor_w, .block, .block, .block, .block, .block, .block,
            .block, .block, .block, .conveyor_w, .block, .block, .block, .block, .block, .block,
            .block, .block, .block, .conveyor_w, .block, .block, .block, .block, .block, .block,
            .block, .block, .block, .conveyor_w, .block, .block, .block, .block, .block, .block,
            .block, .block, .block, .block, .block, .block, .block, .block, .block, .block,
            .block, .block, .block, .block, .block, .block, .block, .block, .block, .block,
            .block, .block, .block, .block, .block, .block, .block, .block, .block, .block,
            .block, .block, .block, .block, .block, .block, .block, .block, .block, .block,
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
            .air, .air, .air, .air, .air,
            .air, .air, .block, .block, .air,
            .air, .air, .block, .block, .air,
            .air, .air, .block, .air, .air,
            .air, .air, .air, .air, .air,
        });
        const newproduct = game.Product{
            .id = @intToEnum(game.ProductID, 1),
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
