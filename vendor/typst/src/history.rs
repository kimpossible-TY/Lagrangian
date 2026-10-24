//! State retained between layout attempts, independent of finished output trees.

use std::any::Any;
use std::sync::Arc;

use typst_html::HtmlDocument;
use typst_layout::PagedDocument;
use typst_library::foundations::Output;
use typst_library::introspection::Introspector;

pub(crate) enum LayoutHistory<T> {
    Introspector(Arc<dyn Introspector>),
    // Output is public and downstream targets need not expose an owned
    // introspector. Preserve their existing lifetime without a new trait bound.
    Output(T),
}

impl<T: Output> LayoutHistory<T> {
    pub(crate) fn new(document: T) -> Self {
        let output = &document as &dyn Any;
        if let Some(html) = output.downcast_ref::<HtmlDocument>() {
            Self::Introspector(html.introspector().clone())
        } else if let Some(paged) = output.downcast_ref::<PagedDocument>() {
            Self::Introspector(paged.introspector().clone())
        } else {
            Self::Output(document)
        }
        // For known targets, document is dropped here. Memoized computations
        // can still own shared output data; this only releases history's owner.
    }

    pub(crate) fn introspector(&self) -> &dyn Introspector {
        match self {
            Self::Introspector(introspector) => introspector.as_ref(),
            Self::Output(document) => document.introspector(),
        }
    }
}
