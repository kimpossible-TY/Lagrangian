use std::sync::Arc;

use super::*;
use typst_html::{HtmlDocument, HtmlNode};
use typst_layout::{Page, PagedDocument};
use typst_library::diag::FileResult;
use typst_library::foundations::{Bytes, Content, Datetime, Duration, Smart};
use typst_library::layout::{Frame, Size};
use typst_library::text::{Font, FontBook};
use typst_syntax::Source;
use typst_utils::LazyHash;

struct TestWorld {
    library: LazyHash<Library>,
    book: LazyHash<FontBook>,
    fonts: Vec<Font>,
    source: Source,
}

impl TestWorld {
    fn new(text: &str) -> Self {
        let fonts: Vec<_> = typst_assets::fonts()
            .flat_map(|data| Font::iter(Bytes::new(data)))
            .collect();
        Self {
            library: Library::builder()
                .with_features(Features::from_iter([Feature::Html]))
                .build()
                .into(),
            book: FontBook::from_fonts(&fonts).into(),
            fonts,
            source: Source::detached(text),
        }
    }
}

impl World for TestWorld {
    fn library(&self) -> &LazyHash<Library> {
        &self.library
    }
    fn book(&self) -> &LazyHash<FontBook> {
        &self.book
    }
    fn main(&self) -> FileId {
        self.source.id()
    }
    fn source(&self, id: FileId) -> FileResult<Source> {
        assert_eq!(id, self.main());
        Ok(self.source.clone())
    }
    fn file(&self, id: FileId) -> FileResult<Bytes> {
        self.source(id).map(|s| Bytes::from_string(s.text().to_owned()))
    }
    fn font(&self, index: usize) -> Option<Font> {
        self.fonts.get(index).cloned()
    }
    fn today(&self, _: Option<Duration>) -> Option<Datetime> {
        None
    }
}

// Exercise upstream's original retention through the public Output contract,
// without adding a baseline mode or a second compiler algorithm to production.
struct FullOutput<T>(T);

impl<T: Output> Output for FullOutput<T> {
    fn target() -> Target {
        T::target()
    }
    fn create(
        engine: &mut Engine,
        content: &Content,
        styles: StyleChain,
    ) -> SourceResult<Self> {
        T::create(engine, content, styles).map(Self)
    }
    fn introspector(&self) -> &dyn Introspector {
        self.0.introspector()
    }
}

#[test]
fn paged_history_releases_pages_and_shares_exact_introspector() {
    let mut pages = eco_vec![Page {
        frame: Frame::soft(Size::zero()),
        bleed: Default::default(),
        fill: Smart::Auto,
        numbering: None,
        supplement: Content::empty(),
        number: 1,
    }];
    let document = PagedDocument::new(pages.clone(), Default::default());
    let introspector = document.introspector().clone();
    assert!(!pages.is_unique());
    let retained = LayoutHistory::new(document);
    assert!(pages.is_unique(), "history must release the page container");
    assert!(std::ptr::addr_eq(
        retained.introspector(),
        introspector.as_ref() as &dyn Introspector
    ));
    assert_eq!(Arc::strong_count(&introspector), 2);
    drop(retained);
    assert_eq!(Arc::strong_count(&introspector), 1);
}

#[test]
fn html_history_releases_nodes_and_shares_exact_introspector() {
    let world = TestWorld::new("Hello");
    let mut document = compile::<HtmlDocument>(&world).output.unwrap();
    // This output-only allocation has no memoization owner or introspectible tags.
    let mut children = eco_vec![HtmlNode::text("output payload", Span::detached())];
    document.root_mut().children = children.clone();
    let introspector = document.introspector().clone();
    assert!(!children.is_unique());
    let retained = LayoutHistory::new(document);
    assert!(children.is_unique(), "history must release the HTML tree");
    assert!(std::ptr::addr_eq(
        retained.introspector(),
        introspector.as_ref() as &dyn Introspector
    ));
}

#[test]
fn unknown_output_keeps_original_lifetime() {
    let document = PagedDocument::new(EcoVec::new(), Default::default());
    let introspector = document.introspector().clone();
    let retained = LayoutHistory::new(FullOutput(document));
    assert!(matches!(retained, LayoutHistory::Output(_)));
    assert_eq!(Arc::strong_count(&introspector), 2);
    drop(retained);
    assert_eq!(Arc::strong_count(&introspector), 1);
}

fn compare<T: Output>(
    source: &str,
    succeeds: bool,
    converges: bool,
    export: impl Fn(&T) -> Vec<u8>,
) {
    let world = TestWorld::new(&format!("#let probe = 40 + 2\n#probe\n{source}"));
    let compact = compile::<T>(&world);
    let full = compile::<FullOutput<T>>(&world);
    assert_eq!(
        compact.output.is_ok(),
        succeeds,
        "{source}: {:?}",
        compact.output.as_ref().err()
    );
    assert_eq!(
        !compact
            .warnings
            .iter()
            .any(|w| w.message.contains("did not converge")),
        converges,
        "{source}"
    );
    assert_eq!(format!("{:?}", compact.warnings), format!("{:?}", full.warnings));
    match (compact.output, full.output) {
        (Ok(a), Ok(b)) => assert_eq!(export(&a), export(&b.0)),
        (Err(a), Err(b)) => assert_eq!(format!("{a:?}"), format!("{b:?}")),
        _ => panic!("compact and full history disagree on success"),
    }
    fn literal(node: &typst_syntax::SyntaxNode) -> Option<Span> {
        if node.kind() == typst_syntax::SyntaxKind::Int {
            return Some(node.span());
        }
        node.children().find_map(literal)
    }
    let span = literal(world.source.root()).expect("probe literal");
    assert!(!trace::<T>(&world, span).is_empty(), "trace must exercise a value");
    assert_eq!(
        format!("{:?}", trace::<T>(&world, span)),
        format!("{:?}", trace::<FullOutput<T>>(&world, span)),
    );
}

#[test]
fn output_diagnostics_and_trace_match_full_history() {
    for (source, succeeds, converges) in [
        ("Plain $x^2$.", true, true),
        (
            "#set heading(numbering: \"1.\")\nSee @later.\n= Later <later>\n#context counter(heading).display()",
            true,
            true,
        ),
        ("#context query(heading).len()\n= First\n= Second", true, true),
        (
            "#let s = state(\"s\", 0)\n#context s.update(s.final() + 1)\n#context s.final()",
            true,
            false,
        ),
        ("See @missing.", false, true),
        ("#panic(\"expected failure\")", false, true),
    ] {
        compare::<HtmlDocument>(source, succeeds, converges, |doc| {
            typst_html::html(doc, &Default::default()).unwrap().into_bytes()
        });
        compare::<PagedDocument>(source, succeeds, converges, |doc| {
            typst_pdf::pdf(doc, &Default::default()).unwrap()
        });
    }
}
