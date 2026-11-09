# Personas and selection engine review — 2026-11-09

AUDIT RESULT: FAIL

## Findings

- **MEDIUM — full-repository analysis exits 1.** The latest run reported 151 diagnostics (146 info, 5 warnings). None are in the 54 changed Dart files; focused analysis of those files exited 0 with three info-level findings and no errors or warnings. The first global warning is in lib/agent/context/character_context_assembler.dart:117, outside this diff.
- **LOW — previous full-suite timeout did not reproduce.** The latest complete run passed 1,616 tests, skipped 2, and had no failures.
- **LOW — saved profiles retain their current content.** By the owners earlier choice, the merge applies to new PT/EN seeds only; existing persona YAML and workspaces were preserved without bulk rewrite or migration.

## Changes reviewed

- Consolidated `Gerente de escopo` and `Parceiro de foco` into the new `Facilitador de execução` seed, with separate scope and next-step modes that activate only when requested. New seed count is 14 in Portuguese and English; legacy IDs remain recognized for compatibility.
- Renamed `Cobrador de prazo` to `Acompanhante de prazos` and `Calmo na crise` to `Calmo em incidentes`; narrowed incident routing to operational incidents and aligned deadline wording across languages.
- Removed random persona fallback. Single selection requires the best candidate to lead by at least two affinity points; otherwise it uses the primary companion or no persona. Matching uses whole words/phrases to avoid substring false positives.
- Included each persona's comment policy in multi-persona routing. The selector prefers one useful voice and may select none; a valid empty LLM result remains empty.
- Preserved previous refinements: ignore filters, Portuguese fatigue/venting affinity, bounded input excerpts, debate relevance ordering, editable interest filter, prompt overrides/style examples, and post-history instructions in proactive initiative.

## Review checks

- Focused persona tests from the prior review: 39 passed.
- Full flutter test --no-pub --reporter compact: 1,616 passed, 2 skipped, 0 failures.
- dart analyze on the 54 changed Dart files: exit 0; three info-level findings, no errors or warnings.
- flutter analyze --no-pub: exit 1; 151 findings (146 info, 5 warnings), none in the changed Dart files.
- flutter build apk --debug --flavor globalDev --no-pub: PASS; APK package app.segundamente.dev, version 1.0.41+126.
- Installed on the connected S25 Ultra (SM-S938B, RQCY10934YV) with adb install -r; Package Manager reports versionCode 126 and versionName 1.0.41.
- git diff --check: PASS.
- Real-model persona conversation after installation: NOT_RUN. F10-01 through F10-04 remain REVIEW; F10-05 remains IN_PROGRESS; F10-06 remains BLOCKED.
