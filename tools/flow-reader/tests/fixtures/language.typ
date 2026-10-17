#set text(lang: "en")
#include "responsive-math.typ"
#include "native-canvases.typ"

= Languages in the original content

// Typst 0.15.1 exports the document language but does not yet emit local text
// language attributes. Explicit HTML parts exercise preservation by the Reader.
#html.elem("span", attrs: (lang: "fr"))[Bonjour. Cette phrase reste en français.]

#html.elem("span", attrs: (lang: "ko"))[이 문장은 원문에서도 한국어입니다.]
