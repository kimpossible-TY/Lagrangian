// Only the isolated compiler overlay receives mutable request data.
#let inputs() = json("requests.json")
#let geometry(kind) = if sys.inputs.at("flow-live", default: "false") == "true" {
  inputs().at(kind, default: (:))
} else {
  json(bytes(sys.inputs.at("flow-" + kind, default: "{}")))
}
