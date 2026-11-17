#set page(width: 420pt, height: 640pt, margin: 24pt)
#set text(size: 14pt)
= Isolated native Reader inspection <intro>

Source and chat probe: independently authored content for exact mapping.

Select across paragraphs. Plain copy and accessibility may span more than 32 blocks;
source and chat submission retain their narrower fragment limit.

#for i in range(1, 38) [
  Paragraph #i: 한글 한글 é 😀 👩‍👩‍👧‍👦 office ffi abc אבג 123.

]

== Mathematics <math>
Inline $frac(1, 2) + alpha$ remains beside prose.

$ frac(x^2 + 1, y + 2) = integral_0^1 t dif t $ <fraction>

#table(columns: 2, table.header([Item], [Value]), [Fraction], [$frac(1, 2)$], [Unicode], [한글 😀])

== Images and navigation <images>
#image("pixels.png", width: 48pt, height: 24pt)

#figure(image("shape.svg", width: 72pt), caption: [Owned blue vector]) <vector>

#link(<intro>)[Return to the inspection heading].
External #link("https://example.invalid/native-inspection")[link target; do not open].

== Conversation <conversation>
Ask a question only with Send. The fixture provider returns an authored TeX fraction.
Prefix a question with [lost-ack] to drop its first successful mutation response;
then use Refresh conversation. This is a test transport fault, never real inference.
