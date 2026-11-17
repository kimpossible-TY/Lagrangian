// Controlled NR10 source. CRLF is intentional; no private project input.
#set text(font: "Helvetica")
= Start <start>

#link(<start>)[First] _emphasis_ and #link(<finish>)[jump].

한글

한글

é

😀

👩‍👩‍👧‍👦

office ffi

abc אבג 123

Tab	end.

CRLF left
right.

Repeated paragraph carries enough ordinary words to wrap at narrow widths and preserve logical reading order across every font size in the matrix. Selection must retain these words exactly after reflow.

= Finish <finish>

Repeated paragraph carries enough ordinary words to wrap at narrow widths and preserve logical reading order across every font size in the matrix. Selection must retain these words exactly after reflow.

Inline $x + 1$ done.

#table(columns: 2, table.header([Name], [Value]), [A], [B])

#let pixel = bytes((137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,2,0,0,0,2,8,2,0,0,0,253,212,154,115,0,0,0,15,73,68,65,84,120,156,99,96,96,248,15,70,96,10,0,23,246,3,253,126,235,55,243,0,0,0,0,73,69,78,68,174,66,96,130))
#figure(image(pixel, format: "png", width: 64pt), caption: [Controlled figure.])
