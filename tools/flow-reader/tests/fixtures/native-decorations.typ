#import "@preview/mannot:0.4.0": mark
#set math.equation(numbering: "(1)")
= Native semantic decorations

$ cancel(x^2 + y_1 + a + b + c + d + e + f + g + h + i + j + k + l)
  = overline(alpha + beta) $ <wide-cancel>

// Resolved set rules must survive the callback, including a function angle.
#[
  #set math.cancel(stroke: (paint: red, thickness: 1.5pt, dash: "dashed"),
    cross: true, length: 130%, angle: angle => angle + 10deg)
  $ cancel(mark(a + b + c, color: #purple)) = 0 $ <custom-cancel>

  $ cancel(p + q, cross: #false, inverted: #true, angle: #30deg, stroke: #blue,
    length: #(100% + 0.6em)) = 1 $
]

$ cancel(mark(frac(1, 2) T^(j k) (nabla_j Z^k - nabla_k Z^j), color: #blue),
    cross: #false, inverted: #false, angle: #auto, stroke: #0.05em) = 2 $

The conjugate remains semantic: $overline(z_1^2 + z_2^2)$.

Reference @wide-cancel and @custom-cancel.
