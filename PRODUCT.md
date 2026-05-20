# Product

## Register

product

## Users

Undergraduate students at James Madison University, most of them new to academic planning. They open this app to build a semester-by-semester pathway through their declared major, see what's left before graduation, and explore catalog programs before committing. Context: a Mac at a desk, often during advising prep, late at night during course registration windows, or before a meeting with an advisor. Many have never used a planning tool before; some are first-generation college students who have no inherited mental model for how degree requirements connect.

## Product Purpose

Turn JMU's published undergraduate catalog into a personal pathway a student can actually live with: pick a major, declare transfer credit, set a workload preference, and get three concrete pathway drafts that respect prerequisites, semester availability, and General Education clusters. Then let the student drag courses around with real-time conflict feedback. Success = a student walks into an advising meeting with a saved, printable plan and a list of intelligent questions, instead of a blank stare.

## Brand Personality

Calm, scholarly, refined. The voice of a sharp older sibling who has read the catalog and translated it. Not chipper, not corporate, not athletic. Tone is plain English at a freshman reading level without being condescending. JMU's Royal Purple (#450084) and Gold (#CBB677) act as accents on a quiet neutral surface, not as a brand-flag waved at the user.

## Anti-references

- **Generic SwiftUI / default Mac apps.** No default System gray with a single blue accent, no untreated form controls, no "this clearly used the Xcode template" feel.
- **1990s university registrar portals.** No gray-on-gray table density, no abbreviation-soup column headers, no Submit-and-pray buttons that lead to a 503.
- **Crypto / fintech dark mode neon.** No glowing gradient hero metrics on pure black, no purple-pink neon, no decorative chart-as-art.
- **Corporate enterprise dashboard cliché.** No "big number, small label, sparkline, generic blue" hero metric template. No identical card grids stamped across the screen.

## Design Principles

1. **Talk to a freshman on day one.** Every label, tooltip, and error message reads like a real person explaining the thing to someone who has never heard of "Cluster Three" or "course override". Jargon dies on first sight.
2. **Two clicks to anywhere.** Every major feature (schedule edit, transfer credit, course detail, progress tracker, export) is reachable from the main screen in two clicks or fewer. If a feature needs three, the navigation is wrong.

## Accessibility & Inclusion

- WCAG AA contrast in both light and dark mode, validated through the centralized `DesignTokens` color tokens.
- Honors the macOS `Reduce Motion` setting and the system appearance setting (no in-app theme toggle).
- Baseline keyboard navigation and screen-reader behavior is whatever SwiftUI's `@MainActor` defaults provide. No custom screen-reader work is in scope yet; if a target user surfaces a specific need, expand from there.
- Course codes, credit counts, percentages, and projected-graduation dates use tabular numerals so values align in lists and stay scannable for students who scan visually rather than read.
