# Schedule generation progress UI

## Goal

When the user kicks off pathway generation — from setup, the My Plan footer, or the Schedule board — show a centered modal overlay with a determinate progress bar and a per-pathway stage label, so the app no longer appears frozen while `ScheduleGenerator.generatePathways` runs.

## Why

`PlanStore.generateSchedules()` runs synchronously on the main thread. Generation can take a couple of seconds on real catalogs (especially after a fresh open-elective top-up adds ~13 placeholders interleaved across pathways). With nothing on screen during that window the user reasonably concludes the app has crashed and force-quits, losing their setup.

## Out of scope

- Cancellation. The recent perf fix (open-elective `courseLevel` short-circuit) brings generation back into the sub-second range on typical majors. YAGNI a cancel button until users report wanting one.
- Reporting per-semester progress. The visible signal is "pathway N of 3 — <name>"; finer detail wouldn't help the user and would require instrumenting `buildSemesters`.
- Background refresh. Generation only runs in response to an explicit user action; no need to debounce or schedule.

## Threading

`PlanStore.generateSchedules()` becomes `async`. The heavy `ScheduleGenerator.generatePathways(...)` call runs on a background-priority `Task.detached`. The detached task captures only `Sendable` inputs (`Catalog`, `WorkloadPreference`, `[TransferCredit]`, `[Program]`, `String` IDs). Results hop back to `@MainActor` for `plan.pathways` assignment, `errorMessage` clear, and `autosave()`.

Each call site wraps the call in `Task { await store.generateSchedules() }` — Setup sheet's "Generate Plan" button, MyPlanView's "Regenerate pathways" button, and ScheduleBoardView's "Regenerate" button. SetupSheet's existing "dismiss the sheet on success" behavior is preserved by checking `store.errorMessage == nil` after the `await` resolves.

## State

`PlanStore` gains one new `@Published` field:

```swift
struct ScheduleGenerationProgress: Equatable {
    var current: Int       // 1-indexed pathway number
    var total: Int         // total pathway count (currently 3)
    var pathwayName: String
}

@Published var scheduleGenerationProgress: ScheduleGenerationProgress?
```

`nil` means idle. While set, the overlay is visible and all "Regenerate" buttons are disabled (prevents double-fire).

## Scheduler hook

`ScheduleGenerator.generatePathways` gets an optional trailing closure:

```swift
public func generatePathways(
    for programID: String,
    concentrationID: String? = nil,
    workload: WorkloadPreference,
    transferCredits: [TransferCredit],
    starting start: SemesterIdentity = ...,
    additionalPrograms: [Program] = [],
    progress: (@Sendable (Int, Int, String) -> Void)? = nil
) throws -> [Pathway]
```

Inside the existing `for (index, variant) in variants.enumerated()` loop, the closure fires once per variant immediately before `buildSemesters` runs:

```swift
progress?(index + 1, variants.count, pathwayName(index + 1))
```

The closure is invoked from the background task; PlanStore wraps its body in `await MainActor.run { ... }` (or assigns via the actor) to publish safely.

## UI

A new `ScheduleGenerationOverlay` SwiftUI view lives at `Sources/JMUCoursePlanner/Views/Overlays/ScheduleGenerationOverlay.swift`. Shown via `.overlay { ... }` on the root `ContentView` when `store.scheduleGenerationProgress != nil`.

Structure:

- Full-screen ZStack
- Background: `Color.black.opacity(0.4)` + `.contentShape(Rectangle())` + an `.onTapGesture {}` no-op — swallows taps so the UI behind is unreachable
- Centered Card containing:
  - Title "Generating pathways" (`Typography.heading`)
  - Subtitle "Building pathway \(current) of \(total) — \(pathwayName)"
  - Determinate `ProgressView(value: Double(current), total: Double(total))` tinted with `brandGold`
  - No cancel button

The Card uses existing design tokens — same `Card` wrapper used elsewhere, centered with a fixed width (~360pt) and reasonable padding.

## Errors

`generateSchedules()` wraps the work in `do/catch`. On `catch`:

```swift
errorMessage = error.localizedDescription
scheduleGenerationProgress = nil
```

Overlay dismisses, the existing error-message banner surfaces the failure in whichever view is current. Pre-flight guards (no major selected, concentration missing) still set `errorMessage` synchronously without entering the async path.

## Tests

- Default-arg `progress: nil` keeps all 67 existing tests green with no edits.
- Optional new unit test in `ScheduleGeneratorTests`: assert closure invoked exactly `variants.count` times, in order, with correct names. Not required to ship.

## Risks

- **`Task.detached` capture safety:** all inputs verified `Sendable` (catalog, workload, transfer credits, additional programs are all immutable value types or `Sendable` per existing model). The detached task must NOT capture the PlanStore directly — it only receives plain values, returns a result, and the awaiting `@MainActor` body writes back.
- **Concurrent regenerate:** disable all three buttons while `scheduleGenerationProgress != nil`; the store also short-circuits to a no-op if called while in flight.
- **Setup sheet flow:** SetupSheet currently calls `store.generateSchedules()` then dismisses on success. Wrap in `Task { await ... ; if store.errorMessage == nil { dismiss() } }`. Keep the existing UX on success/failure.
