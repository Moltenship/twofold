# Twofold

Twofold is a lightweight, native, open-source alternative to DuoBar, the menu bar mark app.

## What makes Twofold special

1. Open at the core.
2. Performance without compromise. Lots of apps have gotten bogged down with bad tech decisions and "slop". We have not, and we're proud of how little Twofold costs the Mac it runs on.

## A small glossary

- **you**: means the agent reading this file and changing Twofold.
- **we, us, and maintainers**: mean Timofey, and the people building Twofold. These are who you are talking to now.
- **user**:  means the person using Twofold.
- **alternative**: means DuoBar, the closed-source app Twofold is an alternative to.

## Note from the maintainer

I like ambitious ideas, simple systems, and software that feels obvious. Do not preserve complexity just because it already exists. Do not introduce machinery because it looks architecturally impressive. Understand the real constraint, then fight for the smallest model that makes the correct behavior unsurprising.

Channel both "measure twice, cut once" and "yagni". Fight scope creep. Try to honor the dev's intent in both a minimal and realistic fashion.

The rest of this document is meant to help you navigate the codebase and make changes effectively. Think of these instructions less as "hard rules", more as "good defaults". The developer's preferences should be able to override anything here

## Pull Requests

- Conventional commit titles, plain language: fix(web): new threads no longer spike CPU.
- UI changes need before/after images. Motion or timing needs a short video. (these should be attached via gh --attach to the PR description).
- Upload PR evidence to GitHub. Never commit PR-only screenshots or assets such as .github/pr-assets/.

## Documentation

- All documentation should be in English. You may answer to the user in any language that user wants, but the docs should be in English.
- `docs/internals/` is for architectural decisions and their reasons, constraints that span components, and implementation traps that are hard to discover from the source. Before adding a paragraph, ask what a maintainer would get wrong without it. If reading the relevant code answers the question, leave it out.
- Do not document every feature, enumerate fields or methods, narrate control flow, maintain file catalogs, or append PR summaries. Types, tests, and code already record the implementation. The glossary defines shared vocabulary; it is not a feature index.
- A local reason the code can't show goes in a short nearby code comment. Use an internal doc when the reasoning crosses boundaries or needs context the code cannot carry well. Link to the relevant source instead of copying it.
- When a documented decision or constraint changes, rewrite or remove the affected text. Do not append another account of the new behavior. A new internal page needs a distinct, durable reason to exist.
- `docs/user/` helps users accomplish tasks. Give each major feature a concise section explaining what it does, how to start, and anything unintuitive. A settings path is useful; descriptions of visible buttons, icons, layouts, animations, or every UI state are not. Before adding text, ask what task or decision it helps the user with.
- Keep user docs in the shipped product's voice, without implementation details or contributor tooling. Update the relevant feature section when how to use it changes. A UI tweak does not need a documentation entry, and a new control does not need its own page.
- `docs/operations/` holds maintainer setup, release, and debugging procedures.
- `docs/feature-map.md` is Twofold's own feature map: what we build, priorities, release slices, what stays out of scope, and the requirements per feature. When a product decision changes, rewrite the affected entry there.
- `docs/feature-reference/` records how the alternative behaves, as observed. `feature-map-reference.md` is the index. Each feature has a folder with `feature.md` and screenshots. Keep it to facts about the alternative: what it does, its hotkeys, texts, and quirks. Twofold decisions belong in `docs/feature-map.md`, which links to the reference. Mark anything unverified as such. Take screenshots on synthetic data only, never personal data or license details. This folder is committed on purpose. It is the one exception to the research-notes rule below.
- Do not commit implementation plans, research notes, or agent scratch files. Keep temporary working material outside the worktree. .plans/ is gitignored only as a safety net for legacy tooling.

## Building and UI checks

- `swift build` compiles; `scripts/build-app.sh` makes `dist/Twofold.app` (ad-hoc signed) and `scripts/build-app.sh --run` relaunches it. There is no Xcode project and none is needed.
- `Twofold --render-unfold <dir>` writes the mark at every frame of the unfold as PNGs, so motion changes can be compared frame by frame with the strips in `docs/feature-reference/02-unfold/`.
- Screenshots of the menu bar come from `screencapture -R`; record motion with `ffmpeg -f avfoundation -framerate 60` and cut it into tiles. Touch only Twofold's own windows, and never commit screenshots with personal data (device names, network names, IP addresses, volume names).

## Taste
- Complexity belongs at the adapter boundary. UI stays dumb.
- Default to no comment. Write one only for a constraint, an external quirk, or an invariant the code can't show, in one line where you can and four at most. Don't restate names or signatures, narrate steps, record history, or explain the fix you just made; the PR carries that.
