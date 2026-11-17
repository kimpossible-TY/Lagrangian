# Design

The existing paragraph-chat controller retains selection, snapshot, transport,
streaming and host history ownership. A keyed ChatTranscript in content.js owns
message presentation, preserving focused/open question-context details while
answer deltas arrive. Original user text, selection and revision stay literal.

Markdown-it 12.3.2 is reused from the existing dependency as an unmodified static
distribution. Tokens become an allowlisted DOM vocabulary; model output never
enters innerHTML. Images become alt text and links accept only HTTP(S)/mailto
without credentials. TeX is bounded, delimited and rendered only on completion
through the existing MathJax 4.1.3 loader with base+AMS. No require/autoload/HTML
extensions are loaded. Failed, unsupported or unfinished mathematics retains its
source. Generation tickets prevent late typesetting into newer message nodes.

Expanded panels inherit paper/ink/accent and reading size. Small system labels
separate context, question, answer and follow-up. Hairlines replace bulky cards.
The canonical toolbar logo is unchanged. Collapsed geometry is unchanged.

During an accepted stream the submitted question is already in the transcript.
Hide that duplicate in the composer without deleting its durable draft; restore
it after failure or interruption unless the user has started a different draft.
Display known provider progress in Korean and leave unknown messages intact.

The composer compares its captured context revision with the accepted document
before enabling Send. A stale but reattached conversation explains how to select
the paragraph again; earlier message contexts and drafts remain intact. Request
errors belong to the conversation view and survive ordinary rerenders until that
operation succeeds or the reader explicitly refreshes its selected context.

`draft-recovery.js` owns a bounded sessionStorage recovery copy keyed by document
and conversation. It contains only up to 8000 characters of composer text and,
after an explicit Send, that pending message ID. No history, source context or
credentials are copied. On reload the controller reconciles the copy against
the host's exact saved draft or accepted user-message identity before displaying
it. Unacknowledged text is restored with a visible notice; the current host draft
remains available in details, and automatic draft writes/pagehide flushes pause
until the user explicitly saves or sends the recovered text. Acknowledgment
removes the recovery copy, without deleting newer edits or resurrecting text if
storage removal fails. Unavailable tab storage retains editing in memory, shows
a saving/copying notice, and adds a beforeunload guard only while those volatile
edits remain unacknowledged. Mobile lifecycle termination is not assumed to
deliver beforeunload; the visible notice covers that limitation.
The host remains authoritative for history and all model dispatch.

Each host run writes one bounded timing report to the existing stderr log. The
provider marks authentication readiness, per-round request/headers/first event/
first text/completion and bounded document-tool boundaries with monotonic elapsed
milliseconds. The host aggregates source validation and storage write counts and
durations; source validation includes concurrent cancellation checks, so summed
cost is not a disjoint wall-time partition. Only allowlisted stage names,
nonnegative integer round indices (including round 9 and later), numeric
durations/counts, a schema version and terminal outcome enter the report. No
document, prompt, answer, tool arguments/results, identity, model, credential,
URL, path or exception text is recorded. Reports do not enter
conversation history, model input or the browser protocol. Each report retains
at most 96 events; saturation only stops diagnostic collection, never document
exploration. Diagnostics cannot block terminal job cleanup if the log is
unavailable.

Live traces showed the 50 ms upstream cancellation watcher repeatedly hashing the
same accepted sources in parallel with event validation. Each run now owns a
serialized validation result. Visible provider events, document tools, initial
dispatch and completion force a full validation; they never use the cached
result. Idle/provider cancellation polls reuse it for at most 500 ms, while
explicit cancellation, closure, revision changes and compilation remain checked
on every poll. Thus an idle upstream still closes after a saved-source edit even
without another SSE byte or a publication, and a source edit immediately before
a delta cannot admit that delta through the recent idle result.

One dialog per controller holds read-only connection status and the configured
Homepage account-management link. Each composer opens that same dialog. The
Homepage prerequisite owns account composition and Mac-only mutation authority;
document auth remains status/models-only. Model selection stays per composer.
The completed Homepage and chat changes are copied as sanitized source into a
new publication branch rooted at the existing remote proposal and current main.
