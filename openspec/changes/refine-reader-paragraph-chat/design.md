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

One dialog per controller holds the existing account UI and memory-only host
capability. Each composer links to that dialog. Mac loopback/origin/capability
checks are unchanged. Homepage integration owns replacing renderAccount/auth;
the chat presentation calls shared account rendering once and models separately.
No Homepage source is copied or modified by this work.
