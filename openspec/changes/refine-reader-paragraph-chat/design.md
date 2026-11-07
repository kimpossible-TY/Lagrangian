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

Each host run writes one bounded timing report to the existing stderr log. The
provider marks authentication readiness, per-round request/headers/first event/
first text/completion and bounded document-tool boundaries with monotonic elapsed
milliseconds. The host aggregates source validation and storage write counts and
durations; source validation includes concurrent cancellation checks, so summed
cost is not a disjoint wall-time partition. Only allowlisted stage names, numeric
round indices, numeric durations/counts, a schema version and terminal outcome
enter the report. No document, prompt, answer, tool arguments/results, identity,
model, credential, URL, path or exception text is recorded. Reports do not enter
conversation history, model input or the browser protocol. Diagnostics cannot
block terminal job cleanup if the log is unavailable.

One dialog per controller holds read-only connection status and the configured
Homepage account-management link. Each composer opens that same dialog. The
Homepage prerequisite owns account composition and Mac-only mutation authority;
document auth remains status/models-only. Model selection stays per composer.
The completed Homepage and chat changes are copied as sanitized source into a
new publication branch rooted at the existing remote proposal and current main.
