#import "@local/math-blocks:0.2.0": flowbox
#set math.equation(numbering: "(1)")

Before the derivations.
#flowbox()[
  $ chevron.l L v, v chevron.r = 0 $ <single-vector>
]

Now, let's expand it to the entire vector space $V$.
#flowbox()[
  $
    0 &= chevron.l L (v_0 + v_1), v_0 + v_1 chevron.r
      = chevron.l L v_0 + L v_1, v_0 + v_1 chevron.r
    \
    &= chevron.l L v_0 + L v_1, v_0 chevron.r
      + chevron.l L v_0 + L v_1, v_1 chevron.r
    \
    &= cancel(chevron.l L v_0 comma v_0 chevron.r)
      + chevron.l L v_1, v_0 chevron.r
    \
    &+ chevron.l L v_0, v_1 chevron.r
      + cancel(chevron.l L v_1 comma v_1 chevron.r)
  $

  $arrow.b$

  $ chevron.l L v_1, v_0 chevron.r = -chevron.l L v_0, v_1 chevron.r $

  $arrow.b$

  Use @single-vector
  $ therefore chevron.l L v_1, v_0 chevron.r = -chevron.l v_1, L v_0 chevron.r $
]
After the derivations.
