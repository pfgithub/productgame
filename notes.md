- top down
- zachlike
- physical, continuous map. maybe somewhat open world but probably quite gated
  behind either knowledge, unlocks, or physical gates
  - we don't have to start with this, we can start as individual levels and then link stuff
     together
- histograms (we'll want to validate solutions serverside probably. shouldn't be too hard)

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