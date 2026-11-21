#set page(width: 600pt, height: auto, margin: 16pt)
#set text(size: 14pt)
#let picture() = image("blue.png", width: 24pt, height: 12pt, alt: "blue")
#context if target() == "html" {
  html.elem("p")[before#picture()after]
} else { [before#picture()after] }
