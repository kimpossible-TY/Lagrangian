## 1. Activity signals

- [x] 1.1 Retain per-pipeline compiler state and deliver initial/live status frames; test late viewers and errors.
- [x] 1.2 Add DOM render, selection-held and failure callbacks; verify selection release and render failures.

## 2. Browser feedback

- [x] 2.1 Add initial HTML ring and localized activity controller with safe-area placement and reduced motion.
- [x] 2.2 Connect renderer, transport and compiler lifecycle; test state precedence and recovery.

## 3. Validation and documentation

- [x] 3.1 Document activity in the Typst guide and regenerate preview assets; run scoped TypeScript, Rust and formatting checks.
- [x] 3.2 Verify loading, successful render, live update, compiler error and reconnect in an isolated browser; record delivery limits.
- [x] 3.3 Apply the user-authorized installed-app update and verify status transitions plus actual production document rendering.

## 4. Selection wait clarification

- [x] 4.1 Identify selection-held updates as paused, hide the loading ring, and provide an accessible localized selection-release action.
- [x] 4.2 Verify release resumes queued rendering, preserve selection until explicit release, and update the guide and behavior contract.

Validation: 26 focused activity, selection and theme unit tests; frontend TypeScript and preview build; 300-page real-engine Chromium and WebKit touch/keyboard selection-release smoke; generated guide consistency; strict OpenSpec validation. WebKit verification caught cancelled pointerdown suppressing tap clicks; the release action now permits pointerdown. This follow-up changes source and generated local assets only; installed-app delivery and physical iPhone verification remain separate.

## 5. Install selection feedback

- [ ] 5.1 Build and verify a signed app from the clean selection-feedback commit, preserving the existing signing identity.
- [ ] 5.2 Install with recovery backup, restore the previously running profiles, and verify production HTML and both-theme document delivery.
