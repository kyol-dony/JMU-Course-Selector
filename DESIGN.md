---
name: JMU Course Planner
description: A calm, scholarly Mac app for JMU undergraduates building their semester-by-semester pathway.
colors:
  royal-purple: "#450084"
  royal-purple-dark: "#7c3aed"
  royal-purple-soft: "#f4f0fa"
  royal-purple-soft-dark: "#1f1530"
  madison-gold: "#cbb677"
  madison-gold-dark: "#b8a168"
  paper: "#fafafa"
  paper-dark: "#0a0a0c"
  card-paper: "#ffffff"
  card-paper-dark: "#15151a"
  hairline: "#e4e4e7"
  hairline-dark: "#2a2a30"
  ink-stroke: "#a1a1aa"
  ink-stroke-dark: "#52525b"
  ink: "#0a0a0c"
  ink-dark: "#fafafa"
  body-gray: "#52525b"
  body-gray-dark: "#a1a1aa"
  quiet-gray: "#71717a"
  verified-green: "#16a34a"
  verified-green-dark: "#22c55e"
  advisor-amber: "#d97706"
  advisor-amber-dark: "#f59e0b"
  hard-stop-red: "#dc2626"
  hard-stop-red-dark: "#ef4444"
typography:
  display:
    fontFamily: "system-ui, -apple-system, 'SF Pro Text', 'Inter', sans-serif"
    fontSize: "28px"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "-0.01em"
  title:
    fontFamily: "system-ui, -apple-system, 'SF Pro Text', 'Inter', sans-serif"
    fontSize: "22px"
    fontWeight: 600
    lineHeight: 1.2
  heading:
    fontFamily: "system-ui, -apple-system, 'SF Pro Text', 'Inter', sans-serif"
    fontSize: "18px"
    fontWeight: 600
    lineHeight: 1.3
  body:
    fontFamily: "system-ui, -apple-system, 'SF Pro Text', 'Inter', sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.45
  bodyEmphasized:
    fontFamily: "system-ui, -apple-system, 'SF Pro Text', 'Inter', sans-serif"
    fontSize: "14px"
    fontWeight: 600
    lineHeight: 1.45
  label:
    fontFamily: "system-ui, -apple-system, 'SF Pro Text', 'Inter', sans-serif"
    fontSize: "13px"
    fontWeight: 500
    lineHeight: 1.3
  caption:
    fontFamily: "system-ui, -apple-system, 'SF Pro Text', 'Inter', sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.4
  small:
    fontFamily: "system-ui, -apple-system, 'SF Pro Text', 'Inter', sans-serif"
    fontSize: "11px"
    fontWeight: 500
    lineHeight: 1.3
    letterSpacing: "0.04em"
rounded:
  rail: "3px"
  chip: "6px"
  button: "8px"
  card: "12px"
  pill: "999px"
spacing:
  xs: "4px"
  s: "8px"
  m: "12px"
  l: "16px"
  xl: "24px"
  xxl: "32px"
  xxxl: "48px"
components:
  button-primary:
    backgroundColor: "{colors.royal-purple}"
    textColor: "{colors.card-paper}"
    rounded: "{rounded.button}"
    padding: "12px 16px"
    typography: "{typography.bodyEmphasized}"
  button-primary-pressed:
    backgroundColor: "{colors.royal-purple}"
    textColor: "{colors.card-paper}"
  button-secondary:
    backgroundColor: "{colors.card-paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.button}"
    padding: "12px 16px"
    typography: "{typography.bodyEmphasized}"
  button-tertiary:
    backgroundColor: "{colors.card-paper}"
    textColor: "{colors.royal-purple}"
    rounded: "{rounded.button}"
    padding: "4px 8px"
    typography: "{typography.label}"
  button-destructive:
    backgroundColor: "{colors.card-paper}"
    textColor: "{colors.hard-stop-red}"
    rounded: "{rounded.button}"
    padding: "12px 16px"
    typography: "{typography.bodyEmphasized}"
  card:
    backgroundColor: "{colors.card-paper}"
    rounded: "{rounded.card}"
    padding: "16px"
  course-chip:
    backgroundColor: "{colors.card-paper}"
    rounded: "{rounded.chip}"
    padding: "8px 12px"
    typography: "{typography.bodyEmphasized}"
  stat-chip:
    backgroundColor: "{colors.card-paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    padding: "8px 12px"
    typography: "{typography.bodyEmphasized}"
  status-pill:
    backgroundColor: "{colors.royal-purple-soft}"
    textColor: "{colors.royal-purple}"
    rounded: "{rounded.pill}"
    padding: "3px 8px"
    typography: "{typography.small}"
  progress-rail:
    backgroundColor: "{colors.hairline}"
    rounded: "{rounded.rail}"
    height: "6px"
---

# Design System: JMU Course Planner

## 1. Overview

**Creative North Star: "The Catalog, Translated"**

The printed JMU 2026-2027 Undergraduate Catalog is the source material. This app is its translation: the same authority, the same scholarly restraint, but rendered for a freshman at a Mac at midnight. Surfaces feel like tinted paper. Royal Purple acts as ink-mark, never as banner. Madison Gold sits in the margin: course-code accents, the lone JMU monogram, a notation. The grid is calm. The numbers are tabular and aligned. Nothing shouts.

The system rejects four reflexes. It rejects the default Mac app look (System gray, single blue accent, untreated form controls). It rejects the 1990s registrar portal (gray-on-gray tables, abbreviation-soup headers). It rejects the crypto/fintech dark mode (neon, gradient hero metrics on pure black). And it rejects the corporate enterprise dashboard cliché (big number, small label, sparkline, generic blue). When a choice feels like it might be one of those, we stop and choose otherwise.

**Key Characteristics:**
- Light AND dark modes auto-follow macOS appearance; neither is the default.
- Royal Purple appears on ≤10% of any given screen. Madison Gold is rarer still.
- Numbers (course codes, credits, percentages, dates) use tabular figures and align vertically across lists.
- Cards lay flat. Borders carry elevation; shadows are a whisper, not a lift.
- Type does the work. Hierarchy is built from scale and weight, not from color or chrome.

## 2. Colors

A neutral paper-toned canvas, two brand colors used sparingly, three semantic signals reserved for status. Every neutral is tinted slightly toward the brand hue (zinc / cool gray family) so the palette holds together when Royal Purple appears anywhere on the screen.

### Primary
- **Royal Purple** (`#450084` light / `#7c3aed` dark): JMU's official brand color. Used on primary buttons, the active-tab pill in the top bar, the completion percentage on the My Plan stat tile, the verification ring on category-deep-link hover. Vivid in dark mode so it stays unmistakable against near-black surfaces.
- **Royal Purple Soft** (`#f4f0fa` light / `#1f1530` dark): The selected-row tint in the catalog browser, the highlight color on the Setup workload radio, the soft fill on info status pills. A whisper of the brand, not a flag.

### Secondary
- **Madison Gold** (`#cbb677` light / `#b8a168` dark): Marginalia. The "J" inside the small JMU monogram in the top bar. The 3px left-border accent on General Education course chips. Never used on text larger than 12px. Slightly desaturated in dark mode so it doesn't vibrate.

### Neutral
- **Paper** (`#fafafa` light / `#0a0a0c` dark): The workspace canvas. The space tabs and cards rest on.
- **Card Paper** (`#ffffff` light / `#15151a` dark): The elevated surface for cards, the top bar, the setup sheet.
- **Hairline** (`#e4e4e7` light / `#2a2a30` dark): The 1px border on every card, the divider beneath the top bar, the progress rail track.
- **Ink Stroke** (`#a1a1aa` light / `#52525b` dark): Heavier borders, the unselected workload radio outline, the kebab-menu glyph at rest.
- **Ink** (`#0a0a0c` light / `#fafafa` dark): Body text and headings. The default reading color.
- **Body Gray** (`#52525b` light / `#a1a1aa` dark): Secondary text: helper lines under headings, the department line under a program title, "of 24 credits" copy beneath progress rails.
- **Quiet Gray** (`#71717a`): Tertiary text: credit-count chips on course cards, the "small uppercase" eyebrow labels.

### Semantic
- **Verified Green** (`#16a34a` light / `#22c55e` dark): The "Verified" status pill on programs with parsed requirements. The "Complete ✓" line beneath a finished progress rail.
- **Advisor Amber** (`#d97706` light / `#f59e0b` dark): The "Partial" status pill for unverified data. The progress rail fill when a category needs advisor verification. The inline warning strip beneath an offending course chip.
- **Hard Stop Red** (`#dc2626` light / `#ef4444` dark): The 3px left border on a course chip with an active prerequisite or semester conflict. Destructive button text. Reset App Data.

### Named Rules

**The Ink-Mark Rule.** Royal Purple is the writer's pen, not the page. It appears on ≤10% of any given screen: primary action, active tab, one completion number. If Royal Purple is fighting for space with another color, the design is wrong.

**The Marginalia Rule.** Madison Gold is reserved for notation: the monogram, the gen-ed category accent, and nowhere else. It never carries text larger than 12px. It never tints a card background.

**The Semantic Lane Rule.** Verified Green, Advisor Amber, and Hard Stop Red appear only on status pills, progress rails, and warning strips. They never become a default surface. They never carry decorative weight.

## 3. Typography

**Display Font:** macOS system font (SF Pro on Mac, Inter fallback noted in the stack).
**Body Font:** same. Single-family system.

**Character:** A quiet, technical, well-spaced sans serif with tabular numerals enabled wherever a number appears in a list. The personality comes from rhythm: tight tracking on display sizes, loose on uppercase eyebrows, body lines capped at a comfortable reading width.

### Hierarchy
- **Display** (700, 28px, line-height 1.15, tracking -0.01em): Program titles on the My Plan hero card. Course code in the Course Detail sheet header.
- **Title** (600, 22px): Setup sheet header. Donut hero text on the Progress tab.
- **Heading** (600, 18px): Section headers across My Plan, Progress, and the Course Detail sheet.
- **Body** (400, 14px): Default reading text. Program descriptions, requirement notes, course titles. Line length is capped by container width (cards are ≤1100px, course detail sheet is 480px) so body never approaches the AI-slop wall-of-text feel.
- **Body Emphasized** (600, 14px): The bolded course code in a CourseChip. Stat chip values in the top bar. Card titles.
- **Label** (500, 13px): Tab pill text. Tertiary button text. Workload radio titles.
- **Caption** (400, 12px): Credit counts beneath progress rails. Card sub-info. Tertiary explanatory copy.
- **Small** (500, 11px, tracking 0.04em, uppercase): Eyebrow labels above stat tiles ("COMPLETION", "PROJECTED GRADUATION"), the degree-type pill text, the stat-chip labels in the top bar.

### Named Rules

**The Tabular Numerals Rule.** Anywhere a number lives next to another number (credit counts, percentages, projected graduation years, course numbers in chip stacks), use the `monospacedDigit()` SwiftUI modifier or the `tabular-nums` font feature. Aligned numerals are the difference between scannable and slop.

**The One-Family Rule.** No display font, no editorial serif, no monospace. The system font alone, weighted and scaled, carries every level of hierarchy. The voice is one voice.

## 4. Elevation

Flat with one whisper of shadow. Cards sit on the Paper canvas with a 1px Hairline border. In light mode only, a soft `0 1px 2px rgba(0,0,0,0.06)` shadow gives the card the faintest lift, like paper resting on a wider sheet. In dark mode the shadow disappears entirely; the border alone carries elevation. Nothing else uses shadow.

### Shadow Vocabulary
- **Card-rest** (`box-shadow: 0 1px 2px rgba(0,0,0,0.06)`, light mode only): The single elevation in the system. Applied to every `Card` primitive. Never combined with a stronger shadow on the same surface.

### Named Rules

**The Border-First Rule.** Elevation is communicated through the 1px Hairline border, not through shadow. If a surface needs to feel raised, give it the border. The shadow is a closing detail in light mode, not the lifting mechanism.

**The No-Glass Rule.** No `backdrop-filter`, no blurred translucent cards, no glassmorphism. The system is paper, not glass. The macOS materials (`.regularMaterial`, `.ultraThinMaterial`) are not used in this design.

## 5. Components

### Buttons
- **Shape:** 8px corner radius (gently curved, not pill).
- **Primary** (`button-primary`): Royal Purple fill, Card Paper text, padding 12px / 16px, Body Emphasized typography. Used for the single most important action on a screen: Generate Plan in the Setup sheet, Start Setup in the empty state, Retry on the loading view.
- **Secondary** (`button-secondary`): Card Paper background, Ink text, 1px Hairline border, same padding and typography as primary. Used for "Edit setup" footers, "Back" in the Setup sheet, "Regenerate" in the Schedule sub-toolbar.
- **Tertiary** (`button-tertiary`): No background, Royal Purple text, Label typography, padding 4px / 8px. Used for "Skip", "Keep" on warning strips, "Regenerate pathways".
- **Destructive** (`button-destructive`): Card Paper background, Hard Stop Red text, Hard Stop Red 50%-alpha 1px border. Used only for Reset App Data and Start Over.
- **Pressed state:** Primary darkens via 85% opacity; Secondary fills with the Royal Purple Soft tint; Destructive fills with Hard Stop Red 15%-alpha.

### Chips
- **CourseChip:** Card Paper background, 6px corner radius, 1px Hairline border, internal padding 8px / 12px, a 3px left-border accent in one of four colors: Royal Purple (major core), Madison Gold (gen ed), Quiet Gray (free elective), Hard Stop Red (active warning). Hover reveals a small Hard Stop Red trash icon in the top-right corner. When a category filter is active in My Plan, contributing chips gain a 2px Royal Purple outer ring.
- **StatChip:** Card Paper or Royal Purple Soft (emphasized variant) pill, 1px Hairline border, padding 8px / 12px. Two text spans: an 11px uppercase eyebrow label in Quiet Gray, and a 14px tabular-numeric value in Ink (or Royal Purple when emphasized).
- **StatusPill:** Filled 999px pill, padding 3px / 8px, 11px text. Tones: Verified Green (success), Advisor Amber (warning), Hard Stop Red (danger), Royal Purple (info), Hairline-50% (neutral). Optional 9px bold leading SF Symbol.

### Cards
- **Corner Style:** 12px (gently curved).
- **Background:** Card Paper.
- **Shadow Strategy:** Card-rest, light mode only (see Elevation).
- **Border:** 1px Hairline.
- **Internal Padding:** 16px default; 12px on dense variants (SemesterColumn).

### Inputs
- **TextField:** Uses SwiftUI's `.roundedBorder` style as a deliberate concession: matches the macOS Mail / Notes feel, no custom-built field. Background is `Card Paper`, border is the system's default 1px treatment which closely matches Hairline.
- **Steppers and Pickers:** Native SwiftUI controls, untreated. Sit on Card Paper inside Cards.

### Navigation
- **TopBar (64px tall):** Card Paper background, 1px Hairline bottom edge. Three clusters: left (28px JMU monogram in Royal Purple with a Madison Gold "J", program title + degree pill), center (four-tab pill control on Paper canvas with a Hairline border), right (StatChips for completion + graduation, an optional "Refreshing" pill, the ellipsis menu).
- **Tab pills:** Active = Royal Purple fill, white text; inactive = transparent fill, Body Gray text. 150ms ease-out animation when the active tab changes.

### ProgressRail (signature component)
The 6px rounded bar that lives under every category and graduation total. The rail itself is Hairline; the fill is Royal Purple when verified, Advisor Amber when partial. The fill carries a 1px inset `rgba(0,0,0,0.06)` overlay so the depth reads in both modes without becoming a gradient. Beneath the rail, a single 12-pt caption line lists up to 5 remaining required course codes, followed by "+ N more" when more exist. At 100%, the helper reads "Complete ✓" in Verified Green. Categories with no specific courses (free electives, partial gen ed clusters) show a credit-only helper: "X credits to plan".

## 6. Do's and Don'ts

### Do:
- **Do** use Royal Purple on the single most important action of any screen, and nowhere else (`The Ink-Mark Rule`).
- **Do** use Madison Gold only on the monogram and gen-ed accent (`The Marginalia Rule`).
- **Do** enable tabular numerals (`.monospacedDigit()` / `tabular-nums`) on every number that appears in a list (`The Tabular Numerals Rule`).
- **Do** lead elevation with the 1px Hairline border; let the shadow be a closing whisper in light mode only (`The Border-First Rule`).
- **Do** list remaining required courses beneath every category progress rail, capped at 5 with "+ N more" overflow.
- **Do** use the system font at the documented weights; no extra families (`The One-Family Rule`).
- **Do** test every change in both light and dark macOS appearance before shipping.

### Don't:
- **Don't** ship default Mac chrome. The Xcode template look (System gray, single blue accent, untreated form controls) is the first anti-reference in PRODUCT.md.
- **Don't** build a 1990s registrar portal. Gray-on-gray tables, abbreviation-soup headers, and dense data dumps are forbidden.
- **Don't** use crypto/fintech dark mode neon. No glowing gradient hero numbers on pure black. No purple-pink neon. No decorative chart-as-art.
- **Don't** ship the corporate enterprise dashboard cliché: big number, small label, sparkline, generic blue. No "hero metric template", no identical card grids stamped down the page.
- **Don't** use `border-left` greater than 1px on cards, list items, callouts, or alerts. The 3px CourseChip accent is the single exception, justified because the chip itself is a list item with a category color that needs to be visible inside the column.
- **Don't** apply `background-clip: text` with a gradient. No gradient text anywhere. Emphasis comes from weight and size, period.
- **Don't** use glassmorphism, backdrop blurs, or `.ultraThinMaterial`. The system is paper, not glass.
- **Don't** use em dashes in copy. Use commas, colons, semicolons, periods, or parentheses.
- **Don't** introduce a new font family. No display serif, no monospace, no Inter alongside SF Pro. One family carries the whole system.
- **Don't** invent a verification status. If a JMU policy or course requirement cannot be confirmed from the catalog, mark it Partial and explain why in the source note. Surface the uncertainty, never paper over it.
