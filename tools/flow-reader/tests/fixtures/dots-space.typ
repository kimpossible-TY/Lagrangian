#import "@local/math-blocks:0.2.0": dots_space

#set page(width: 18cm, height: auto, margin: 1cm)
#set text(size: 12pt)
#set math.equation(numbering: "(1)")

= Standalone
Before helper #dots_space after helper.

= Inline
Inline formula $alpha #dots_space beta$ remains in this paragraph.

Reference formula $alpha dots.h.c beta$ is the HTML spacing control.

= Aligned display
$
  a &= b #dots_space c \
  d &= e #dots_space f
$ <dots-aligned>

= Nested math
Nested formula $x^(#dots_space) + frac(1, #dots_space) + mat(#dots_space, 1; 2, 3)$ stays inline.

= Numbering
$ z = 1 $ <dots-after>
References @dots-aligned and @dots-after.
