#import "@local/text-utils:0.1.2": highlighted
#set heading(numbering: "1")

= Authored highlights

#highlighted[Plain highlighted text.]

#highlighted("A highlighted string.")

#highlighted[One text child.]

#highlighted[Mixed text $Gamma_(i j)^k$ and a tall fraction $frac(a + b, c + d)$ remain highlighted.]

#highlighted[The *nested expression $sqrt(x^2 + y^2)$* and #link(<target>)[its reference] keep their structure.]

#highlighted[$a + b + c + d + e + f + g + h + i + j + k + l + m + n + o + p$]

#highlighted[$ frac(1, 1 + x^2) = y $]

#highlighted[
  First highlighted paragraph.

  Second highlighted paragraph.
]

This ordinary expression $x^2 + y^2 = 1$ has no highlight. <target>
