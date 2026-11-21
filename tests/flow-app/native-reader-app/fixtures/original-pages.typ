#set page(width: 320pt, height: 360pt, margin: 20pt)
#set text(size: 14pt)
#if sys.inputs.at("flow-reader", default: "") == "true" {
  [= Original page fixture
  Accepted HTML #read("html.txt")]
} else {
  let extra = read("pdf.txt")
  for i in range(256) {
    [= Page #i
    Native PDF #extra.
    FarNeedle#i
    #link("https://example.invalid/reader")[Safe URI]
    #if i == 0 { link(<last-page>)[Go to last] }
    #if i == 255 [Last page <last-page>]
    ]
    if i < 255 { pagebreak() }
  }
}
