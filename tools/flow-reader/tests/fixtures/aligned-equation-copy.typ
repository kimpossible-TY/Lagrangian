#let s = (tag: name => label(name),)
#set math.equation(numbering: n => "(3.4.48)")

$
  u^b(t,x)
  &= integral_(bb(R)^n) p_t^((n))(x-y) f^b(y) thin d y \
  &= sum_(gamma in Gamma) integral_(Q+gamma) p_t^((n))(x-y) f^b(y) thin d y \
  &= integral_Q lr([sum_(gamma in Gamma) p_t^((n))(x-z+gamma)]) f(z) thin d z.
$ #(s.tag)("periodic-cell-solution")
