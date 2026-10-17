#import "@preview/cetz:0.4.2"
= Automatic drawing delivery

#cetz.canvas({
  import cetz.draw: *
  rect((0, 0), (16, 8), stroke: 1pt)
  line((0, 0), (16, 8))
  content((8, 10), [First label #linebreak() second line #linebreak() third line])
})

#block[Keep this paragraph at the same reading position while drawings load and
the reading size changes. Its mathematical text $a+b=c$ remains in the body.] <reading-position>

#cetz.canvas({
  import cetz.draw: *
  rect((0, 0), (20, 3), stroke: 1pt)
  content((10, 1.5), [Second label])
})

#for i in range(24) [
  Reading paragraph #i. The ordinary vertical flow continues while the original
  drawing program is compiled at the requested width and reading size.

]
#link(<reading-position>)[Return to the reading paragraph.]
