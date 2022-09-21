// this is a small sdl app that executes
// `zig build run`
// on the application with a specified zig binary.
// it will display a little progress bar or something.
// eventually, it will use -Drelease-fast probably.

//
// - note:
//   - we might be able to use this to do hmr
//   - that would mean: this app initializes the window and then builds
//     the game as a dynamic library and loads it with the library load function
//     and calls into the library on each frame
// - if we can do that, that should be the next thing we do because it is very useful
//

// the plan is if this ever gets to a releasable stage, we could release the game in
// source code form (copyright © all rights reserved header on every file) but
// it makes it trivial to mod