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
  madison-gold-ink: "#7d6419"
  madison-gold-ink-dark: "#b8a168"
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
- **Royal Purple Soft** (`#f4f0fa` light / `#1f1530` dark): The selected-row tint in the catalog browser, the fill on selected Setup option cards, the soft fill on info status pills. A whisper of the brand, not a flag.

### Secondary
- **Madison Gold** (`#cbb677` light / `#b8a168` dark): Marginalia. The "J" inside the small JMU monogram in the top bar. The 3px left-border accent on General Education course chips. Never used on text larger than 12px. Slightly desaturated in dark mode so it doesn't vibrate.

**The Gold-on-Purple Rule.** Royal Purple text or glyphs never sit on a purple surface. Wherever Royal Purple Soft or a Royal Purple wash shows (at rest, on hover, on press, or when selected), purple content on it turns Madison Gold Ink: tertiary button text while hovered or pressed, the placeholder chip while tinted, setup selection checks, the current step number, a selected workload's range, icon tiles, and the numeral on a selected year badge. Borders and rings may stay purple. This rule takes precedence over the Marginalia Rule's 12px cap.

- **Madison Gold Ink** (`#7d6419` light / `#b8a168` dark): The gold that text and glyphs take on Royal Purple Soft or a light purple wash (see the Gold-on-Purple Rule). Light Madison Gold reads at about 1.9:1 on that wash; the ink shade reaches about 5:1. Gold on solid Royal Purple (the active tab, the monogram, a selected year badge) keeps the brighter Madison Gold, which already contrasts strongly there.

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
- **Advisor Amber** (`#d97706` light / `#f59e0b` dark): The "Partial" status pill for unverified data. The progress rail fill when a category needs advisor verification. The warning tag and resting semester outline for worth-a-look issues (coreq gaps, heavy or light credit load).
- **Hard Stop Red** (`#dc2626` light / `#ef4444` dark): The warning tag and resting semester outline for must-fix issues (missing prerequisite, course not offered that term). Destructive button text. Reset App Data.

### Named Rules

**The Ink-Mark Rule.** Royal Purple is the writer's pen, not the page. It appears on ≤10% of any given screen: primary action, active tab, one completion number. If Royal Purple is fighting for space with another color, the design is wrong.

**The Marginalia Rule.** Madison Gold is reserved for notation: the monogram, the gen-ed category accent, and nowhere else. It never carries text larger than 12px. It never tints a card background.

**The Semantic Lane Rule.** Verified Green, Advisor Amber, and Hard Stop Red appear only on status pills, progress rails, warning tags, and semester outlines. They never become a default surface. They never carry decorative weight.

## 3. Typography

**Display Font:** macOS system font (SF Pro on Mac, Inter fallback noted in the stack).
**Body Font:** same. Single-family system.

**Character:** A quiet, technical, well-spaced sans serif with tabular numerals enabled wherever a number appears in a list. The personality comes from rhythm: tight tracking on display sizes, loose on uppercase eyebrows, body lines capped at a comfortable reading width.

### Hierarchy
- **Display** (700, 28px, line-height 1.15, tracking -0.01em): Program titles on the My Plan hero card. Course code in the Course Detail sheet header.
- **Title** (600, 22px): Setup step titles. Donut hero text on the Progress tab.
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
- **Tertiary** (`button-tertiary`): No background, Royal Purple text, Label typography, padding 4px / 8px. Used for "Skip", "Keep anyway" and fix actions in warning popovers, "Regenerate pathways".
- **Destructive** (`button-destructive`): Card Paper background, Hard Stop Red text, Hard Stop Red 50%-alpha 1px border. Used only for Reset App Data and Start Over.
- **Pressed state:** Primary darkens via 85% opacity; Secondary fills with the Royal Purple Soft tint; Destructive fills with Hard Stop Red 15%-alpha. Every style also dips to 97% scale on press (skipped under Reduce Motion).
- **Hover state:** Primary lifts with a 10% white wash; Secondary's border darkens to Ink Stroke; Tertiary gains a Royal Purple Soft fill and its text turns Madison Gold (Hard Stop Red 8% for a `.destructive` role, which also turns its text red); Destructive gains a 7% red wash. 150ms ease-out.
- **Disabled state:** 45% opacity, no hover. A disabled primary action should sit next to a one-line caption saying what unblocks it.

### Chips
- **CourseChip:** Card Paper background, 6px corner radius, 1px Hairline border, internal padding 8px / 12px, a 3px left rail in the course's subject color (from `CourseClassificationPalette`). **Hover:** a 7% wash of the subject color, border at 35% of the subject color, 1px lift, soft subject-colored shadow (150ms ease-out), and a small Hard Stop Red trash button on a Card Paper circle in the top-right corner. **Press:** scales to 98%. **Dragging:** the floating copy tilts -1.5°, scales to 103%, and casts a deeper neutral shadow; the origin slot keeps a 35% ghost with a dashed border. When a category filter is active in My Plan, contributing chips gain a 2px Royal Purple ring; a chip that the current drag would break gains a 2px Hard Stop Red ring at 45% instead.
- **PlaceholderChip:** transparent fill, 8px corner radius, 1px dashed Royal Purple border. Shares CourseChip's hover lift, ghost, and lifted states with a 6% Royal Purple wash.
- **StatChip:** Card Paper or Royal Purple Soft (emphasized variant) pill, 1px Hairline border, padding 8px / 12px. Two text spans: an 11px uppercase eyebrow label in Quiet Gray, and a 14px tabular-numeric value in Ink (or Royal Purple when emphasized).
- **StatusPill:** Filled 999px pill, padding 3px / 8px, 11px text. Tones: Verified Green (success), Advisor Amber (warning), Hard Stop Red (danger), Royal Purple (info), Hairline-50% (neutral). Optional 9px bold leading SF Symbol.
- **Schedule drag:** while a block is dragged, every semester column shows what a drop there would do: a tinted border (Verified Green 40% fine, Advisor Amber 45% plus 4% fill for a coreq issue, Hard Stop Red 40% plus 4% fill for a broken prereq or unoffered term), a verdict StatusPill in place of the course count, and a one-line reason in place of the credit total. The origin column reads "Current spot". A 3px Royal Purple insertion line with a leading dot marks the drop point and the column's blocks open a gap (spring, response 0.25, damping 0.85). Reduce Motion drops the tilt, lift, and gap; the line and verdicts stay. At rest, a semester's border takes its worst active warning's color (same palette, 1pt, no fill); drag verdicts replace it while dragging. Warnings appear as a one-line tag under a course's title (or beside a semester's credit total for load) that opens a popover with the explanation, catalog caveats, a one-click fix, and Keep anyway.
- **Semester add and delete:** the board's row of semesters is centered when it fits the window and scrolls from the leading edge when it doesn't. A dashed Royal Purple column after the last semester adds the next term; a slim dashed strip between two semesters refills a skipped term. An empty semester shows a small Hard Stop Red trash button in place of its course count. Add controls fade to 35% and ignore clicks while a block is dragged, so columns never shift under the cursor.
- **Regenerate after (anchor pick):** no sheet. "Regenerate after…" puts the board in pick mode: the toolbar shows "Click the last semester to keep", then "Keep through <Semester> · rebuild <Next> onward" with Cancel (Esc) and a primary Rebuild. Each column is one click target. The anchor gets a 2px Verified Green border, faint green fill, and a green "Keep through" lock pill; earlier semesters a thin green border; later semesters dim to 45% with a neutral "Rebuild" pill. Hover previews the anchor with a dashed green border. Warning outlines, drags, popovers, and add/delete controls are off while picking. Green here means "stays as-is", matching the drag verdict for a safe drop.

### Setup sheet
- **Layout:** two panes, 880px minimum. A 248px Paper sidebar holds the step rail and, below a Hairline, "Your plan so far": one row per answer (icon, Caption label, Label value) that fills in as the student goes. Workload joins the summary only on its own step, since it has a default. The main pane is Card Paper: a "Step N of M" Small eyebrow, the step's Title and Body helper, the step body, and a footer.
- **Step rail:** 24px numbered markers joined by 2px connectors. Done steps are a filled Royal Purple circle with a white check and a purple connector below; they are clickable and jump back. The current step is a Royal Purple Soft circle with a 2px purple ring and a Body Emphasized label. Upcoming steps are an Ink Stroke outline with Quiet Gray text.
- **Option cards and rows** (`SetupOptionStyle`): cards for small choice sets (year, workload), borderless rows for long lists (majors, minors). Hover washes 55% Royal Purple Soft and darkens the border; press dips to 98.5%; selected takes the Royal Purple Soft fill, a 1.5px Royal Purple edge, and a Madison Gold check that springs in. Purple content inside an option reads the `setupOptionHighlighted` environment value and turns gold while the wash shows.
- **Footer:** Back (secondary, Cmd-[) on the left; on the right an optional caption explaining a blocked action or the latest error, Skip (tertiary) on optional steps that are still empty, and the step's primary action (Return).
- **Motion:** the step body slides 32px in from the direction of travel and fades, while the outgoing step fades out in 120ms. Under Reduce Motion both are a plain fade. Picking a year holds 350ms on the selected card before moving on.

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
- **Pathway selector** (Schedule toolbar): the tab-pill trough (hairline border, 8px radius, faint Hairline fill) as a quieter sibling of the main tabs. The selected pathway is a raised Card Paper segment with a hairline edge, soft shadow, and Ink text; others are Body Gray and darken to Ink on hover. No Royal Purple. When space is tight every label shortens together, one step at a time ("Gen Ed-First Path" → "Gen Ed-First" → "Gen Ed"), never truncating; the full name is in the tooltip.

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
