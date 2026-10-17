# Responsive mobile reader alongside the paged preview

The current saved-document preview fixes content to printed page geometry. A phone reader must zoom or rotate to read ordinary paragraphs, equations, and figure labels. Add a distinct HTML reading output and frontend to tinymist-flow, sharing the original Typst sources with the existing paged output.

The reader preserves headings, mathematical notation, numbering, references, footnotes, and annotations. Paragraphs reflow at the selected font size. Figures use width-aware layouts; difficult equations retain accurate local rendering and an explicit expanded view. Reader updates preserve the selected passage and reading position.

Implement the reader as independent modules within this repository. Flow owns compilation and project settings; Tail Hosting exposes the new endpoint. Keep the installed paged service and address available throughout development and rollout. Validate the full PDE document, not only a simplified demo, before making the mobile reader the default mobile entry.

Non-goals: replacing Typst's parser or evaluator, removing PDF export, changing mathematical meaning, or automatically inferring a responsive layout from every arbitrary drawing program.
