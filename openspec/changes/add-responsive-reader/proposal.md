# Responsive mobile reader alongside the paged preview

The current saved-document preview fixes content to printed page geometry. A phone reader must zoom or rotate to read ordinary paragraphs, equations, and figure labels. Add a distinct HTML reading output and frontend to tinymist-flow, sharing the original Typst sources with the existing paged output.

The reader preserves headings, mathematical notation, numbering, references, footnotes, and annotations. Paragraphs reflow at the selected font size. Equations and figures are composed to the available reading width at readable text sizes. Essential content is readable in the continuous body without zoom, horizontal panning, slide navigation, or an extra click to expand it. Reader updates preserve the selected passage and reading position.

Implement the reader as independent modules within this repository. Flow owns compilation and project settings; Tail Hosting exposes the new endpoint. Keep the installed paged service and address available throughout development and rollout. Validate the full PDE document, not only a simplified demo, before making the mobile reader the default mobile entry.

Use the existing Tail Dashboard Hosting card as the configured document entry.
Keep a direct open action and browser-local automatic/Reader/original preference.
Only a fresh, healthy, strictly published native Reader qualifies for automatic
touch-device selection; development and unknown runtime flags keep the original
entry. Existing paged bookmarks and both document lifecycles remain unchanged.

Use the semantic HTML/MathML output with a local, width-aware mathematical
renderer. Retain logical token identities across line breaks so selections,
decorations, and original CeTZ relationships follow the new composition. Publish
only validated results for the current document and geometry. Preserve authored
drawing coordinates through shared adapters.
Keep cancellation and overline bodies semantic as well. Original cancellation
properties draw paint around measured fragments; overlines span their full bodies.

Preserve exported source-language metadata separately from localized controls,
including moved mathematical annotations. Managed release switches wait for the
previous Reader job to finish stopping before activating another release.

Provide explicit automatic, light and dark appearances with browser-local persistence.
Use coordinated reading and control palettes, and restrained theme-specific colors
for authored and saved highlights instead of browser-default yellow. Original
drawings and mannot annotations blend into their surrounding reading background,
with readable theme-aware vector paint and label colors.

Non-goals: replacing Typst's parser or evaluator, removing PDF export, changing mathematical meaning, or automatically inferring a responsive layout from every arbitrary drawing program.
