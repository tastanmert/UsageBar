# Third-Party Notices

UsageBar contains no vendored third-party source code. Its only package dependency is Sparkle
(listed below). Several
techniques and patterns were, however, adapted from open-source projects we studied — credited here
both because their licenses ask for it where code was adapted, and because they earned it.

## OpenUsage — MIT License, Copyright (c) 2026 Robin Ebers

<https://github.com/robinebers/openusage>

Patterns adapted (reimplemented in UsageBar's own Swift, closely modeled on theirs):

- **In-view drag-to-reorder** (`UsageBar/Views/CardReorder.swift`): plain `DragGesture` + frame
  preferences + floating lift preview instead of the pasteboard-backed `.draggable` APIs, including
  the crossing-threshold feel and trackpad-haptic discipline. OpenUsage's reorder index math in turn
  credits **crafcat7/Peakmon** (Apache-2.0).
- **Behind-window glass with a rounded mask** (`UsageBar/MenuBar/PinnedPanelController.swift`):
  `NSVisualEffectView` + stretchable rounded `maskImage` for the pinned panel's translucent base.

## headroom — MIT License, Copyright (c) 2026 Paul Domanski

<https://github.com/domanski-ai/headroom>

Concepts adapted (no code ported; UsageBar's implementation is independent Swift):

- **Config-home launching** (`usagebar claude` → `CLAUDE_CONFIG_DIR`/`CODEX_HOME` + exec), including
  the Keychain-namespacing gotcha that the DEFAULT home must launch with the variable unset.
- **Proven-headroom account selection** (only fresh, identity-bound readings are eligible) and the
  **auto-handoff architecture** (resident supervisor → clean terminate → additive transcript copy →
  fork-resume on the next account → rolling-window loop guard).

Where UsageBar deliberately differs: the app is the single usage poller (the CLI reads a published
snapshot and never calls a provider API), launching fails open instead of closed, and cap-hit
detection tails the session transcript rather than installing hooks.

## Sparkle: MIT License

<https://github.com/sparkle-project/Sparkle>

Linked as a Swift package and embedded in the app bundle (`Sparkle.framework`). No update feed is
configured yet, so it does not check for or install updates.

Copyright (c) 2006-2013 Andy Matuschak. Copyright (c) 2009-2013 Elgato Labs. Copyright (c)
2011-2014 Kornel Lesinski. Copyright (c) 2015-2017 Mayur Pawashe. Copyright (c) 2014 C.W. Betts.
Copyright (c) 2014 Petroules Corporation. Copyright (c) 2014 Big Nerd Ranch. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Sparkle also bundles third-party components (for example bspatch, sais and ed25519), each under its
own permissive license; see the LICENSE file in the Sparkle repository for the full list.
