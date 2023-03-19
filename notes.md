## metrics

zachtronics style histograms

measure:

- latency (time from start to first product)
- throughput (time from first product to next product, avg over 100 completions)
- cost (blocks will have a cost value, sum of those)

## interactions

hold shift to change vertical layers. it multiplies your y mouse speed by 0.2, disables x mouse
move, and adjusts the current layer rather than the mouse position

## notes

consider:

https://github.com/hexops/mach/blob/main/examples/triangle/main.zig

webgpu triangle

it's probably too early stage and we'll run into binding and documentation issues unfortunately

## NEXT STEPS

getting tiles rendering:

- in render.zig, write some data to the tiles_data_buffer with glBufferSubData
   - the data: `[width, height, depth, 0]` followed by `[tile_idx, 0, 0, 0][]`
- update the shader to read the data (it has to read the width/height,… first to know what index to read from)
- make some textures. can even program them procedurally on the shader if we want but
  it's probably better to go with images for now
- we can even do connected textures!


## original notes

- top down
- zachlike
- physical, continuous map. maybe somewhat open world but probably quite gated
  behind either knowledge, unlocks, or physical gates
  - we don't have to start with this, we can start as individual levels and then link stuff
     together
- histograms (we'll want to validate solutions serverside probably. shouldn't be too hard)
- [!] device must loop after the first cycle (the state after the second cycle must = the
  state after the first cycle)

there are two layers

- floor, where you build your stuff
- products, where the input and output products come from

ok so a question of:

do we do floating point (non-grid) or integer (grid)

floating point would be ::

- check what an object collides with and check all the things on that surface
- cutting with knives : keep track of all cuts on an object (and draw a line or something
  to visualize and then if a line ever cuts all the way through, split into two surfaces)
- rotators are the only things that rotate stuff. smooth rotation.
- non-grid is an easy way to kill the project because it requires fancy math that i don't know

integer ::

- here's something fun for rendering :: render squares and include a 2d texture containing
  the tile data and then just use opengl]

oh also something to experiment with:

- have no character and lock the mouse to the center of the screen
  - that or keep the mouse within a certain distance of the character

having a character is important for keeping your view restricted in a large map. that or fog of
war.

---

thinking about this made me

- imagine minecraft but infinifactory

anyway might not work for physics, large objects have too many blocks to check while moving

but it would be so cool having factories in minecraft that move blocks around

also, interestingly, everything is always grid-aligned. it only appears offsetted because of
animation.
