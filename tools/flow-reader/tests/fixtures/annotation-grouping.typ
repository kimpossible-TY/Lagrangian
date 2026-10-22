#import "@preview/mannot:0.4.0": mark, markub, markul, core-mark, annot
#let custom = core-mark
#set math.equation(numbering: "(1)")

= Adaptive grouping annotations

$ markub(a+b+c+d+e+f+g+h+i+j+k+l, tag: #<brace-note>, bracket: #sym.brace.b,
    outset: #(x: .4em, bottom: .8em)) = z $
#annot(<brace-note>)[sum]

$ markub(p+q+r+s+t+u+v+w, tag: #<bracket-note>) = 1 $
#annot(<bracket-note>)[This longer explanation follows the complete marked expression through reflow.]

$ mark(underbrace(a+b), tag: #<native-underbrace>)
  + mark(overbrace(c+d), tag: #<native-overbrace>)
  + mark(underbracket(e+f), tag: #<native-underbracket>)
  + mark(overbracket(g+h), tag: #<native-overbracket>) = 0 $
#annot((<native-underbrace>, <native-overbrace>, <native-underbracket>, <native-overbracket>))[groups]

$ mark(underbracket(x+y, "inner name"), tag: #<nested-note>) = 2 $
#annot(<nested-note>)[outer name]

$ markul(alpha+beta, tag: #<underline-note>) = mark(overline(gamma+delta), tag: #<overline-note>) $
#annot(<underline-note>)[underlined]
#annot(<overline-note>)[conjugate]

$ custom(x+y, tag: #<callback-note>,
  overlay: #((w, h, c) => line(start: (0pt, 0pt), end: (w, h), stroke: c))) = 3 $
#annot(<callback-note>)[custom stroke]

// These marks have no text annotation; their grouping must survive.
$ markub(a+b) + markub(c+d, tag: #<tag-only>) + underbrace(e+f) + overbrace(g+h)
  + underbracket(i+j) + overbracket(k+l) = 4 $

// A grouping inside a larger annotated expression has its own meaning.
$ mark(a+underbrace(b+c), tag: #<nested-group>) = 5 $
#annot(<nested-group>)[whole expression]

// An equation-valued argument can wrap the complete grouping as well.
$ mark(#$overbracket(m+n)$, tag: #<equation-note>) = 6 $
#annot(<equation-note>)[equation group]
