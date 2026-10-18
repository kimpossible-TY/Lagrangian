#set math.equation(numbering: "(1)")

= Equation numbers

$ x + y = 1 $ <short>

$ mat(a, b; c, d; e, f) = vec(x, y, z) $ <tall>

$ a &= b + c \
    &= d + e \
    &= f + g $ <multiline>

#counter(math.equation).update(122)
$ a + b + c + d + e + f + g + h + i + j + k + l = 0 $ <long>

#math.equation(block: true, numbering: none)[$x + y = z$] <unnumbered>

Reference to @short and @long.
