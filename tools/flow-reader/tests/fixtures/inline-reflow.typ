#import "@preview/mannot:0.4.0": markhl
= Long inline mathematics

#block[
  Before the expression $frac(1, 2) + S := {markhl(v in T M : gamma_v "is defined on an interval containing" [0, 1], color: #yellow)}$ after the expression.
] <wide-inline>

#block[The control fraction is $frac(1, 2)$.] <control-fraction>

#block[The short expression $a + b$ stays inline.] <short-inline>

#block[
  A reference inside long mathematics $Sigma = {(x, xi) : x in S, xi_j = partial_j v "for" 1 <= j <= n - 1, F(x, xi) = 0} #link(<wide-inline>)[reference]$.
] <linked-inline>

#link(<wide-inline>)[First expression], #link(<control-fraction>)[control],
#link(<short-inline>)[short expression], #link(<linked-inline>)[linked expression].
