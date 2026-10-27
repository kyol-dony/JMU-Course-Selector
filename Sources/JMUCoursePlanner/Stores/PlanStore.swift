import AppKit
import Foundation
import PlannerCore
import SwiftUI

/// Summary of the latest schedule edit, shown in the board's undo toast.
struct ScheduleChange: Identifiable, Equatable {
    let id = UUID()
    /// The undo action name registered for this change, so the toast's Undo
    /// only fires while this change is still on top of the undo stack.
    var actionName: String
    var message: String
    var newWarningCount: Int
}

@MainActor
final class PlanStore: ObservableObject {
    @Published var catalog: Catalog? {
        didSet { cancelPartialRegeneration(); invalidateDerivedState() }
    }
    @Published var plan = SavedStudentPlan() {
        didSet { cancelPartialRegeneration(); invalidateDerivedState() }
    }
    @Published var savedPlans: [SavedStudentPlan] = []
    @Published var selectedCourse: Course?
    @Published var courseDetail: CourseDetail?
    @Published var statusMessage = "Loading JMU catalog data..."
    @Published var errorMessage: String?
    @Published var isRefreshingCatalog = false
    @Published var selectedTab: AppTab = .myPlan
    @Published var setupSheetPresented: Bool = false
    @Published var catalogSelectedProgramID: String?
    @Published var scheduleCategoryFilter: String?
    /// Non-nil while pathway generation is running off-main. Drives the
    /// modal progress overlay and disables the Regenerate buttons.
    @Published var scheduleGenerationProgress: ScheduleGenerationProgress?
    /// Latest schedule edit, for the undo toast. Cleared by undo, redo, and
    /// anything that replaces the pathways.
    @Published var lastScheduleChange: ScheduleChange?
    /// The window's undo manager, injected by ScheduleBoardView.
    var undoManager: UndoManager?

    @Published private(set) var partialRegeneration: PartialRegenerationState?
    var canEditSchedule: Bool { scheduleGenerationProgress == nil && partialRegeneration == nil }
    private var partialGenerationTask: Task<Pathway, any Error>?
    private let anchoredGenerator: any AnchoredScheduleGenerating

    let storageDirectory: URL?
    init(storageDirectory: URL? = nil, anchoredGenerator: any AnchoredScheduleGenerating = LocalAnchoredScheduleGenerator()) {
        self.storageDirectory = storageDirectory
        self.anchoredGenerator = anchoredGenerator
    }
    private let catalogRepository = CatalogRepository()
    private let detailService = CourseDetailService()
    private var courseDetailCache: [String: CourseDetail] = [:]
    private var cachedWarnings: [ConflictWarning]?
    private var cachedAnalysis: PlaceholderPrerequisiteAnalysis?
    private var analysisCacheIsValid = false
    private var cachedProgress: GraduationProgress?
    private var progressCacheIsValid = false
    private var verdictCache: [String: [SemesterIdentity: DropVerdict]] = [:]
    private(set) var verdictRevision = UUID()
    /// Bumped whenever background verdicts land in the cache, so views that
    /// read `cachedDropVerdicts(for:)` (the context menu) refresh.
    @Published private(set) var verdictCacheRevision = 0
    /// In-flight prefetches, keyed by plan version and item, so an edit that
    /// discards one prefetch does not block the next for the new plan.
    private var prefetchingVerdicts: Set<String> = []

    var effectiveAcademicHistory: AcademicHistory {
        let result = EffectiveCreditBuilder.build(records: plan.academicRecords, legacyCredits: plan.transferCredits)
        return .init(records: plan.academicRecords, currentSemester: plan.currentSemester, effectiveCredits: result.credits, earnedHours: result.earnedHours)
    }
    private var earnedHoursContext: Double? {
        plan.studentYear == nil && plan.academicRecords.isEmpty ? nil : effectiveAcademicHistory.earnedHours
    }
    func confirmAcademicHistory(_ history: AcademicHistory) throws {
        guard let catalog else { throw TranscriptReviewError.unresolved([]) }
        var draft = TranscriptReconciler.makeDraft(parsed: nil, catalog: catalog, existingRecords: history.records, existingCredits: [], defaultSemester: history.currentSemester?.id ?? .current())
        draft.setCurrentSemester(history.currentSemester?.id ?? .current())
        let validated = try TranscriptReconciler.confirm(draft, catalog: catalog)
        var updated = plan
        updated.academicRecords = validated.records
        updated.transferCredits = validated.effectiveCredits
        updated.currentSemester = validated.currentSemester
        updated.planningStart = validated.currentSemester?.id
        updated.pathways = []; updated.activePathwayID = nil
        updated.setupCompleted = false
        updated.name = "Autosave"; updated.updatedAt = Date()
        try save(updated)
        plan = updated
        clearScheduleHistory()
        errorMessage = nil
    }
    func syncCurrentEnrollmentFromActivePathway() {
        guard let preserved = plan.currentSemester, let semester = activePathway?.semesters.first(where: { $0.id == preserved.id }) else { return }
        let existing = plan.academicRecords.filter { $0.status == .inProgress }
        plan.academicRecords.removeAll { $0.status == .inProgress }
        for code in semester.courseIDs where !PathwayPlaceholder.isPlaceholder(code) {
            if var row = existing.first(where: { ($0.courseIDs.first ?? $0.code) == code }) {
                row.attemptedCredits = semester.creditOverrides[code] ?? row.attemptedCredits
                plan.academicRecords.append(row)
            } else {
                plan.academicRecords.append(.init(code: code, title: semester.courseTitles[code] ?? catalog?.coursesByID[code]?.title ?? code, courseIDs: catalog?.coursesByID[code] == nil ? [] : [code], attemptedCredits: semester.creditOverrides[code] ?? Double(catalog?.coursesByID[code]?.credits ?? 0), status: .inProgress, source: .manual, matchConfirmed: true))
            }
        }
        var normalized = semester
        let ids = Set(semester.courseIDs)
        normalized.creditOverrides = normalized.creditOverrides.filter { ids.contains($0.key) }
        normalized.courseTitles = normalized.courseTitles.filter { ids.contains($0.key) }
        plan.currentSemester = normalized
    }

    var activeProgram: Program? {
        guard let catalog, let programID = plan.programID else { return nil }
        return catalog.programsByID[programID]
    }

    var activeConcentration: Concentration? {
        guard let activeProgram, let concentrationID = plan.concentrationID else { return nil }
        return activeProgram.concentrations.first { $0.id == concentrationID }
    }

    var requiresConcentrationSelection: Bool {
        guard let activeProgram else { return false }
        return activeProgram.concentrationSelectionRequired && !activeProgram.concentrations.isEmpty
    }

    var majorSelectionComplete: Bool {
        guard let activeProgram else { return false }
        guard requiresConcentrationSelection else { return true }
        guard let concentrationID = plan.concentrationID else { return false }
        return activeProgram.concentrations.contains { $0.id == concentrationID }
    }

    var effectiveActiveProgram: Program? {
        guard let activeProgram else { return nil }
        return try? activeProgram.effectiveProgram(concentrationID: plan.concentrationID)
    }

    var activePathway: Pathway? {
        guard let id = plan.activePathwayID else { return plan.pathways.first }
        return plan.pathways.first(where: { $0.id == id }) ?? plan.pathways.first
    }

    var warnings: [ConflictWarning] {
        if let cachedWarnings {
            return cachedWarnings
        }
        guard let catalog, let activePathway else { return [] }
        let result = ConflictDetector(catalog: catalog).warnings(
            for: activePathway,
            overrides: plan.overrides,
            activeProgramTitle: effectiveActiveProgram?.title,
            // AP / dual-enrollment awards count as completed before the first
            // term so prereq/coreq checks see them the same way the schedule
            // generator does.
            completedAtStart: prerequisiteCreditAtStart,
            workload: plan.workload,
            earnedHoursAtStart: earnedHoursContext,
            prerequisiteAnalysis: placeholderPrerequisiteAnalysis ?? .empty
        )
        cachedWarnings = result
        return result
    }

    /// Which unresolved slots later courses count on, for the current plan.
    /// Computed once per plan/catalog revision and shared by the warnings
    /// and the placeholder pickers; nil when it couldn't finish, which
    /// leaves ordinary conflicts in place.
    var placeholderPrerequisiteAnalysis: PlaceholderPrerequisiteAnalysis? {
        if analysisCacheIsValid { return cachedAnalysis }
        let result: PlaceholderPrerequisiteAnalysis?
        if let catalog, let activePathway {
            result = ConflictDetector(catalog: catalog).placeholderPrerequisiteAnalysis(
                for: activePathway,
                activeProgramTitle: effectiveActiveProgram?.title,
                completedAtStart: prerequisiteCreditAtStart,
                workload: plan.workload,
                earnedHoursAtStart: earnedHoursContext
            )
        } else {
            result = nil
        }
        cachedAnalysis = result
        analysisCacheIsValid = true
        return result
    }

    /// A slot's supporting choices and the courses each supports, from the
    /// current analysis.
    func placeholderDependencies(for placeholderID: String) -> [String: Set<ConditionalDependencyKey>] {
        placeholderPrerequisiteAnalysis?.supportsByPlaceholder[placeholderID] ?? [:]
    }

    /// The picker's explanation for a slot right now; nil when nothing
    /// counts on it (or it's gone). Read at render time, so an open picker
    /// follows edits instead of keeping the labels it opened with.
    func placeholderDependencyPresentation(for placeholderID: String) -> PlaceholderDependencyPresentation? {
        let supports = placeholderDependencies(for: placeholderID)
        guard !supports.isEmpty, let catalog else { return nil }
        return PlaceholderDependencyPresentation(supports: supports, coursesByID: catalog.coursesByID)
    }

    var progress: GraduationProgress? {
        if progressCacheIsValid {
            return cachedProgress
        }
        let result: GraduationProgress?
        if let catalog, let programID = plan.programID, let activePathway {
            result = try? ProgressCalculator(catalog: catalog).progress(
                programID: programID,
                concentrationID: plan.concentrationID,
                pathway: activePathway,
                transferCredits: effectiveAcademicHistory.effectiveCredits,
                additionalPrograms: selectedMinorPrograms(),
                languagePlan: plan.foreignLanguage
            )
        } else {
            result = nil
        }
        cachedProgress = result
        progressCacheIsValid = true
        return result
    }

    private func invalidateDerivedState() {
        cachedAnalysis = nil
        analysisCacheIsValid = false
        cachedWarnings = nil
        cachedProgress = nil
        progressCacheIsValid = false
        verdictCache = [:]
        verdictRevision = UUID()
    }

    /// Effective Program for each added minor (parent program + its selected
    /// concentration's requirements merged). Used to thread minor requirements
    /// into schedule generation and progress tracking.
    func selectedMinorPrograms() -> [Program] {
        plan.minors.compactMap { effectiveMinorProgram(for: $0) }
    }

    /// Set of course IDs the student has completed (transfer credit + scheduled in active pathway).
    var completedCourseIDs: Set<String> {
        var ids = effectiveAcademicHistory.completedCourseIDs
        if let activePathway {
            ids.formUnion(activePathway.semesters.flatMap(\.courseIDs))
        }
        return ids
    }

    /// Course codes still required for a given requirement category, derived from the catalog.
    func remainingCourses(in category: RequirementCategory) -> [String] {
        guard let catalog else { return [] }
        let completed = completedCourseIDs
        let courses = catalog.coursesByID

        if TransferCreditMapper.genEdCreditSatisfies(category: category, completedCourseIDs: completed) {
            return []
        }
        return category.courseOptions.compactMap { option in
            guard !option.contains(where: completed.contains) else { return nil }
            guard let firstID = option.first, let course = courses[firstID] else { return nil }
            return course.code
        }
    }

    func courseIDsForRequirementHighlight(in category: RequirementCategory) -> Set<String> {
        Set(category.courseOptions.flatMap { $0 })
    }

    // MARK: - Placeholder courses in the active pathway

    /// Synthesize a Course for a placeholder ID using its PlaceholderSpec on the
    /// active pathway. Returns the catalog course for normal IDs. Used by views
    /// that render course chips so they don't blow up on placeholder IDs.
    func course(forID id: String) -> Course? {
        // A repeat slot is its course again.
        if let repeated = activePathway?.placeholders[id]?.repeatOf, let course = catalog?.coursesByID[repeated] {
            return course
        }
        if PathwayPlaceholder.isPlaceholder(id),
           let spec = activePathway?.placeholders[id] {
            return Course(
                id: id,
                code: "Choose course",
                title: spec.categoryName,
                credits: Int(ceil(spec.credits)),
                availability: nil,
                prerequisites: [],
                verificationStatus: .partial,
                registrarURL: nil
            )
        }
        if let course = catalog?.coursesByID[id] { return course }
        if let semester = activePathway?.semesters.first(where: { $0.courseIDs.contains(id) }), let title = semester.courseTitles[id] {
            return Course(id: id, code: id, title: title, credits: Int(ceil(semester.creditOverrides[id] ?? 0)), availability: nil, prerequisites: [], verificationStatus: .partial)
        }
        return nil
    }

    /// Replace a placeholder course in the active pathway with the chosen real
    /// course ID. The PlaceholderSpec stays in the pathway's `placeholders`
    /// map (so it can be restored if the user removes the chosen course)
    /// while `resolvedPlaceholders` tracks the mapping for synthetic
    /// progress rows and reversal.
    func resolvePlaceholder(_ placeholderID: String, with chosenCourseID: String) {
        let name = scheduleItemName(chosenCourseID)
        let category = activePathway?.placeholders[placeholderID]?.categoryName ?? "this requirement"
        recordScheduleChange(actionName: "Choose \(name)", message: "Chose \(name) for \(category)") {
            applyResolvePlaceholder(placeholderID, with: chosenCourseID)
        }
    }

    private func applyResolvePlaceholder(_ placeholderID: String, with chosenCourseID: String) {
        guard let pathwayIndex = activePathwayIndex else { return }
        var pathway = plan.pathways[pathwayIndex]
        for semesterIndex in pathway.semesters.indices {
            pathway.semesters[semesterIndex].courseIDs = pathway.semesters[semesterIndex].courseIDs.map { id in
                id == placeholderID ? chosenCourseID : id
            }
        }
        pathway.resolvedPlaceholders[placeholderID] = chosenCourseID
        // Choosing a lecture (CHEM 132 for Physical Principles) brings its lab.
        if let labPairing,
           let semester = pathway.semesters.first(where: { $0.courseIDs.contains(chosenCourseID) })?.id {
            pathway = labPairing.addingLab(for: chosenCourseID, in: semester, to: pathway)
        }
        plan.pathways[pathwayIndex] = pathway
        autosave()
    }

    func load() async {
        do {
            savedPlans = try loadPlans()
            if let autosave = savedPlans.first(where: { $0.name == "Autosave" }) {
                plan = autosave
            }
            setupSheetPresented = SetupFlow.needsInitialSetup(plan: plan)
            await Task.yield()
            catalog = try catalogRepository.loadCatalog()
            validateSelectedConcentration()
            let catalogYear = catalog?.source.catalogYear ?? JMUCatalogConfiguration.catalogYear
            statusMessage = "Catalog loaded from the \(catalogYear) JMU undergraduate catalog cache."
        } catch {
            errorMessage = "The catalog cache could not be opened. First launch needs the bundled catalog data or an internet connection to refresh it."
            statusMessage = error.localizedDescription
        }

        // The bundled seed ships requirement data for only a handful of programs.
        // If most programs are unverified (e.g., this is a fresh install with no
        // cached HTML refresh yet), pull the live JMU catalog so every major has
        // schedulable requirements. The user can still trigger a manual refresh.
        if let catalog, needsInitialRefresh(catalog: catalog) {
            refreshCatalog()
        }
    }

    private func needsInitialRefresh(catalog: Catalog) -> Bool {
        let majors = catalog.programs.filter { $0.kind == .major }
        guard !majors.isEmpty else { return true }
        let schedulable = majors.filter { $0.requirementDataComplete }.count
        // If fewer than 10% of majors can be scheduled, trigger a refresh.
        return Double(schedulable) / Double(majors.count) < 0.1
    }

    func selectProgram(_ program: Program) {
        let previousConcentrationID = plan.concentrationID
        plan.programID = program.id
        if let previousConcentrationID,
           program.concentrations.contains(where: { $0.id == previousConcentrationID }) {
            plan.concentrationID = previousConcentrationID
        } else {
            plan.concentrationID = nil
        }
        plan.pathways = []
        plan.activePathwayID = nil
        clearScheduleHistory()
        // Re-route any previously-entered AP credits through the optimizer now
        // that we know which major to optimize for.
        recomputeAPCredits()
        autosave()
    }

    func selectConcentration(id: String?) {
        guard let activeProgram else { return }
        if let id, activeProgram.concentrations.contains(where: { $0.id == id }) {
            plan.concentrationID = id
        } else {
            plan.concentrationID = nil
        }
        plan.pathways = []
        plan.activePathwayID = nil
        clearScheduleHistory()
        recomputeAPCredits()
        autosave()
    }

    /// Setup opens at this step instead of the start; cleared once shown.
    @Published var setupResumeStep: SetupStep?

    /// What to run once a B.A. student answers the language question that
    /// generating or regenerating stopped to ask.
    enum PendingLanguageAction: Equatable {
        case generate
        case regenerate(after: SemesterIdentity)
    }
    @Published var pendingLanguageAction: PendingLanguageAction?

    /// Courses that count as done before the first planned semester when
    /// checking prerequisites: earned credit, plus the language levels a
    /// placement skips.
    var prerequisiteCreditAtStart: Set<String> {
        effectiveAcademicHistory.completedCourseIDs.union(plan.foreignLanguage?.placementCreditCourseIDs() ?? [])
    }

    /// Opens setup at the language step only; the generation that needed
    /// the answer runs once it is given.
    private func askForLanguage(then action: PendingLanguageAction) {
        pendingLanguageAction = action
        setupResumeStep = .language
        setupSheetPresented = true
    }

    /// Runs the generation or regeneration that stopped to ask the language.
    func continueAfterLanguageAnswer() async {
        await resume(takePendingLanguageAction())
    }

    /// Clears and returns the pending action, so closing the sheet can't
    /// race the Continue button that runs it.
    func takePendingLanguageAction() -> PendingLanguageAction? {
        defer { pendingLanguageAction = nil }
        return pendingLanguageAction
    }

    func resume(_ action: PendingLanguageAction?) async {
        guard let action, plan.foreignLanguage != nil else { return }
        switch action {
        case .generate: await generateSchedules()
        case .regenerate(let cutoff): await regenerateActivePathway(after: cutoff)
        }
    }

    /// Whether a declared major's degree requires a foreign language.
    var requiresForeignLanguage: Bool {
        ForeignLanguagePlan.isRequired(by: [activeProgram].compactMap { $0 } + selectedMinorPrograms())
    }

    func setForeignLanguage(_ language: ForeignLanguagePlan?) {
        plan.foreignLanguage = language
        autosave()
    }

    func setWorkload(_ workload: WorkloadPreference) {
        plan.workload = workload
        autosave()
    }

    func addMinor(_ program: Program) {
        guard !plan.minors.contains(where: { $0.programID == program.id }) else { return }
        plan.minors.append(MinorSelection(programID: program.id))
        autosave()
    }

    func removeMinor(programID: String) {
        plan.minors.removeAll { $0.programID == programID }
        autosave()
    }

    /// Pick (or clear) the concentration / option pathway for an already-added
    /// minor. If `concentrationID` is nil the minor reverts to "any pathway".
    func selectMinorConcentration(minorProgramID: String, concentrationID: String?) {
        guard let index = plan.minors.firstIndex(where: { $0.programID == minorProgramID }) else { return }
        guard let catalog,
              let program = catalog.programsByID[minorProgramID]
        else {
            plan.minors[index].concentrationID = nil
            autosave()
            return
        }
        if let id = concentrationID, program.concentrations.contains(where: { $0.id == id }) {
            plan.minors[index].concentrationID = id
        } else {
            plan.minors[index].concentrationID = nil
        }
        autosave()
    }

    /// Returns the minor's effective program (parent + selected concentration's
    /// requirements merged). Used by the schedule generator and the progress
    /// calculator so the minor's required courses participate in graduation
    /// tracking.
    func effectiveMinorProgram(for selection: MinorSelection) -> Program? {
        guard let catalog, let program = catalog.programsByID[selection.programID] else { return nil }
        guard var effective = try? program.effectiveProgram(concentrationID: selection.concentrationID) else { return nil }
        // Strip Gen Ed categories from second-major / minor effective programs.
        // The primary major already contributes Gen Ed; counting it again would
        // double the credit footprint and force the scheduler to slot duplicates.
        effective.requirements = effective.requirements.filter { !Self.isGenEdRequirement($0) }
        return effective
    }

    private static func isGenEdRequirement(_ category: RequirementCategory) -> Bool {
        category.id.contains("gened") || category.name.lowercased().contains("general education")
    }

    func addAPScore(examName: String, score: Int) {
        guard catalog != nil else { return }
        plan.apScores.append(APScore(examName: examName, score: score))
        recomputeAPCredits()
        autosave()
    }

    /// Rerun the AP credit mapper with the current active program in context so
    /// the optimizer can route each AP score to the variant that knocks out the
    /// most major-required courses. Called whenever the AP score list changes
    /// or the active program changes.
    private func recomputeAPCredits() {
        guard let catalog else { return }
        let independent = plan.transferCredits.filter { EffectiveCreditBuilder.record(from: $0).source != .apMapped }
        let records = plan.academicRecords.map(EffectiveCreditBuilder.migrateLegacySource).filter { $0.source != .apMapped }
        let prior = EffectiveCreditBuilder.build(records: records, legacyCredits: independent)
        let apCredits = TransferCreditMapper(catalog: catalog).credits(forAPScores: plan.apScores, program: effectiveActiveProgram, completedCourseIDs: prior.completedCourseIDs)
        plan.transferCredits = independent + apCredits
        if !plan.academicRecords.isEmpty { plan.academicRecords = records + apCredits.map(EffectiveCreditBuilder.record(from:)) }
    }

    func addDualEnrollment(label: String, courseID: String, credits: Int) {
        plan.transferCredits.append(TransferCredit(sourceDescription: label, courseIDs: [courseID], credits: Double(credits), source: .manual))
        autosave()
    }

    func generateSchedules() async {
        guard canEditSchedule else { return }
        // A plan saved before the language question existed is left alone
        // until it is built again; then setup asks first.
        if requiresForeignLanguage, plan.foreignLanguage == nil {
            askForLanguage(then: .generate)
            return
        }
        guard let catalog, let programID = plan.programID else {
            errorMessage = "Choose a major before generating a plan."
            return
        }
        guard majorSelectionComplete else {
            errorMessage = requiresConcentrationSelection
                ? "Choose a concentration before generating a plan."
                : "Choose a major before generating a plan."
            return
        }

        scheduleGenerationProgress = ScheduleGenerationProgress(current: 0, total: 3, pathwayName: "Preparing")

        // Capture plain Sendable values so the detached task never touches
        // the main-actor store. Progress hops back via MainActor.run.
        let concentrationID = plan.concentrationID
        let workload = plan.workload
        let creditResult = EffectiveCreditBuilder.build(records: plan.academicRecords, legacyCredits: plan.transferCredits)
        guard creditResult.issues.isEmpty else {
            errorMessage = "Review overlapping or invalid prior credit in setup before generating."
            scheduleGenerationProgress = nil
            return
        }
        let transferCredits = creditResult.credits
        let preservedSemester = plan.currentSemester
        let earnedHours = earnedHoursContext
        let planningStart = plan.planningStart ?? SemesterIdentity.current()
        let additionalPrograms = selectedMinorPrograms()
        let languagePlan = plan.foreignLanguage

        let result: Result<[Pathway], Error> = await Task.detached(priority: .userInitiated) {
            do {
                let pathways = try ScheduleGenerator(catalog: catalog).generatePathways(
                    for: programID,
                    concentrationID: concentrationID,
                    workload: workload,
                    transferCredits: transferCredits,
                    starting: planningStart,
                    additionalPrograms: additionalPrograms,
                    preservedSemester: preservedSemester,
                    earnedHoursAtStart: earnedHours,
                    languagePlan: languagePlan,
                    progress: { [weak self] current, total, name in
                        Task { @MainActor in
                            self?.scheduleGenerationProgress = ScheduleGenerationProgress(
                                current: current,
                                total: total,
                                pathwayName: name
                            )
                        }
                    }
                )
                return .success(pathways)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let pathways):
            plan.setupCompleted = true
            plan.pathways = pathways
            plan.activePathwayID = pathways.first?.id
            clearScheduleHistory()
            errorMessage = nil
            autosave()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
        scheduleGenerationProgress = nil
    }

    /// The saved pathway remains unchanged while the worker runs. Every plan
    /// or catalog assignment cancels the token, including programmatic changes
    /// that bypass the board's interaction lock.
    func regenerateActivePathway(after cutoff: SemesterIdentity) async {
        guard canEditSchedule else { return }
        if requiresForeignLanguage, plan.foreignLanguage == nil {
            askForLanguage(then: .regenerate(after: cutoff))
            return
        }
        guard let catalog, let programID = plan.programID, majorSelectionComplete,
              let source = activePathway else {
            errorMessage = "Choose a major and a pathway before regenerating."
            return
        }
        do { _ = try AnchoredScheduleContext(source: source, through: cutoff) }
        catch { errorMessage = error.localizedDescription; return }
        let creditResult = EffectiveCreditBuilder.build(records: plan.academicRecords, legacyCredits: plan.transferCredits)
        guard creditResult.issues.isEmpty else {
            errorMessage = "Review overlapping or invalid prior credit in setup before generating."
            return
        }
        let planID = plan.id
        let operationID = UUID()
        let request = PartialRegenerationRequest(
            catalog: catalog, source: source, cutoff: cutoff, programID: programID,
            concentrationID: plan.concentrationID,
            strategy: .resolve(pathwayID: source.id, index: plan.pathways.firstIndex(where: { $0.id == source.id }) ?? 0),
            workload: plan.workload, transferCredits: creditResult.credits,
            additionalPrograms: selectedMinorPrograms(), earnedHoursAtStart: earnedHoursContext,
            languagePlan: plan.foreignLanguage)
        errorMessage = nil
        partialRegeneration = .init(operationID: operationID, pathwayID: source.id, cutoff: cutoff,
                                    progress: .init(current: 0, total: 1, pathwayName: "Preparing"))
        let generator = anchoredGenerator
        let task = Task {
            try await generator.regenerate(request) { [weak self] progress in
                Task { @MainActor in
                    guard let self, self.partialRegeneration?.operationID == operationID,
                          self.plan.id == planID, self.activePathway == source else { return }
                    self.partialRegeneration?.progress = progress
                }
            }
        }
        partialGenerationTask = task
        do {
            let replacement = try await withTaskCancellationHandler {
                let result = try await task.value
                try Task.checkCancellation()
                return result
            } onCancel: { task.cancel() }
            guard partialRegeneration?.operationID == operationID,
                  plan.id == planID, activePathway == source, !task.isCancelled else { return }
            partialGenerationTask = nil
            partialRegeneration = nil
            applyRegeneratedPathway(replacement, source: source, cutoff: cutoff)
            errorMessage = nil
        } catch {
            guard partialRegeneration?.operationID == operationID else { return }
            partialGenerationTask = nil
            partialRegeneration = nil
            if !(error is CancellationError) {
                errorMessage = "Could not regenerate the later semesters. Your plan is unchanged. " + error.localizedDescription
            }
        }
    }

    func cancelPartialRegeneration() {
        partialGenerationTask?.cancel()
        partialGenerationTask = nil
        partialRegeneration = nil
    }

    private func applyRegeneratedPathway(_ replacement: Pathway, source: Pathway, cutoff: SemesterIdentity) {
        guard let index = plan.pathways.firstIndex(where: { $0 == source }) else { return }
        var replacement = replacement
        replacement.id = source.id
        replacement.name = source.name
        let action = "Regenerate after " + cutoff.displayName
        recordScheduleChange(actionName: action, message: action, synchronizeCurrentEnrollment: false) {
            func containsSubject(_ pathway: Pathway, _ override: ConflictOverride) -> Bool {
                pathway.semesters.contains {
                    $0.id == override.semester &&
                    (override.courseID == ConflictWarning.semesterSubjectID || $0.courseIDs.contains(override.courseID))
                }
            }
            let alternatives = plan.pathways.filter { $0.id != source.id }
            var updated = plan
            updated.pathways[index] = replacement
            updated.overrides.removeAll { override in
                override.semester > cutoff && containsSubject(source, override) &&
                !containsSubject(replacement, override) && !alternatives.contains { containsSubject($0, override) }
            }
            plan = updated
        }
    }

    private struct ScheduleSnapshot: Equatable, Sendable {
        var pathway: Pathway
        var overrides: [ConflictOverride]
        var currentSemester: SemesterPlan?
        var academicRecords: [AcademicCourseRecord]
    }

    private func recordScheduleChange(actionName: String, message: String, synchronizeCurrentEnrollment: Bool = true, _ mutation: () -> Void) {
        guard canEditSchedule, let pathwayIndex = activePathwayIndex else { return }
        let planID = plan.id
        let before = ScheduleSnapshot(pathway: plan.pathways[pathwayIndex], overrides: plan.overrides, currentSemester: plan.currentSemester, academicRecords: plan.academicRecords)
        let warningsBefore = warnings
        mutation()
        if synchronizeCurrentEnrollment { syncCurrentEnrollmentFromActivePathway() }
        autosave()
        guard plan.id == planID,
              let index = plan.pathways.firstIndex(where: { $0.id == before.pathway.id })
        else { return }
        let after = ScheduleSnapshot(pathway: plan.pathways[index], overrides: plan.overrides, currentSemester: plan.currentSemester, academicRecords: plan.academicRecords)
        guard after != before else { return }
        registerUndo(restoring: before, expected: after, planID: planID, actionName: actionName)
        lastScheduleChange = ScheduleChange(
            actionName: actionName,
            message: message,
            newWarningCount: WarningDiff.added(before: warningsBefore, after: warnings).count
        )
    }

    private func registerUndo(
        restoring snapshot: ScheduleSnapshot,
        expected: ScheduleSnapshot,
        planID: UUID,
        actionName: String
    ) {
        guard let undoManager else { return }
        let opensGroup = !undoManager.isUndoing && !undoManager.isRedoing
        let groupsByEvent = undoManager.groupsByEvent
        if opensGroup {
            undoManager.groupsByEvent = false
            undoManager.beginUndoGrouping()
        }
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                store.restore(snapshot, expected: expected, planID: planID, actionName: actionName)
            }
        }
        undoManager.setActionName(actionName)
        if opensGroup {
            undoManager.endUndoGrouping()
            undoManager.groupsByEvent = groupsByEvent
        }
    }

    private func restore(
        _ snapshot: ScheduleSnapshot,
        expected: ScheduleSnapshot,
        planID: UUID,
        actionName: String
    ) {
        cancelPartialRegeneration()
        guard plan.id == planID,
              let index = plan.pathways.firstIndex(where: { $0.id == snapshot.pathway.id }),
              plan.pathways[index] == expected.pathway
        else { return }
        let current = ScheduleSnapshot(pathway: plan.pathways[index], overrides: plan.overrides, currentSemester: plan.currentSemester, academicRecords: plan.academicRecords)
        var updated = plan
        updated.pathways[index] = snapshot.pathway
        updated.currentSemester = snapshot.currentSemester
        updated.academicRecords = snapshot.academicRecords
        // Reverse only this edit's override delta. A later "Keep" is a
        // separate decision, potentially in another pathway, and must survive.
        let addedByEdit = Set(expected.overrides).subtracting(snapshot.overrides)
        updated.overrides.removeAll { addedByEdit.contains($0) }
        for override in snapshot.overrides where !expected.overrides.contains(override) {
            if !updated.overrides.contains(override) { updated.overrides.append(override) }
        }
        updated.activePathwayID = snapshot.pathway.id
        plan = updated
        lastScheduleChange = nil
        autosave()
        let restored = ScheduleSnapshot(pathway: snapshot.pathway, overrides: updated.overrides, currentSemester: updated.currentSemester, academicRecords: updated.academicRecords)
        registerUndo(restoring: current, expected: restored, planID: planID, actionName: actionName)
    }

    /// Undo button in the toast. Only undoes while the toast's change is
    /// still the top undo step; something else done since (typing in a
    /// search field, say) must not be undone in its place.
    func undoLastScheduleChange() {
        defer { lastScheduleChange = nil }
        guard let change = lastScheduleChange,
              let undoManager,
              undoManager.canUndo,
              undoManager.undoActionName == change.actionName
        else { return }
        undoManager.undo()
    }

    private func clearScheduleHistory() {
        undoManager?.removeAllActions(withTarget: self)
        lastScheduleChange = nil
    }

    private func scheduleItemName(_ id: String) -> String {
        if let repeated = activePathway?.placeholders[id]?.repeatOf {
            return course(forID: repeated)?.code ?? repeated
        }
        if PathwayPlaceholder.isPlaceholder(id) {
            return activePathway?.placeholders[id]?.categoryName ?? "Choose course"
        }
        return course(forID: id)?.code ?? id
    }

    func dropVerdicts(for itemID: String) -> [SemesterIdentity: DropVerdict] {
        if let cached = verdictCache[itemID] { return cached }
        guard let catalog, let activePathway else { return [:] }
        #if DEBUG
        let started = Date()
        #endif
        let result = DropVerdictCalculator(catalog: catalog).verdicts(
            moving: itemID,
            in: activePathway,
            overrides: plan.overrides,
            activeProgramTitle: effectiveActiveProgram?.title,
            completedAtStart: prerequisiteCreditAtStart,
            workload: plan.workload,
            earnedHoursAtStart: earnedHoursContext
        )
        #if DEBUG
        let elapsed = Date().timeIntervalSince(started) * 1000
        if elapsed > 30 {
            print("[DropVerdict] \(itemID) took \(Int(elapsed)) ms")
        }
        #endif
        verdictCache[itemID] = result
        return result
    }

    /// Capture immutable inputs on the main actor, then compute without holding
    /// up the pointer. A changed plan/catalog or cancelled view task discards
    /// its result instead of publishing stale advice into a newer drag/menu.
    func loadDropVerdicts(for itemID: String) async -> [SemesterIdentity: DropVerdict]? {
        if let cached = verdictCache[itemID] { return cached }
        guard let catalog, let pathway = activePathway else { return nil }
        let revision = verdictRevision
        let overrides = plan.overrides
        let title = effectiveActiveProgram?.title
        let completed = prerequisiteCreditAtStart
        let earnedHours = earnedHoursContext
        let workload = plan.workload
        let worker = Task.detached(priority: .userInitiated) {
            DropVerdictCalculator(catalog: catalog).verdicts(
                moving: itemID, in: pathway, overrides: overrides,
                activeProgramTitle: title, completedAtStart: completed, workload: workload, earnedHoursAtStart: earnedHours
            )
        }
        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard !Task.isCancelled, revision == verdictRevision else { return nil }
        verdictCache[itemID] = result
        verdictCacheRevision += 1
        return result
    }

    /// Verdicts already computed for the current plan, without computing.
    func cachedDropVerdicts(for itemID: String) -> [SemesterIdentity: DropVerdict]? {
        verdictCache[itemID]
    }

    /// Starts computing verdicts in the background (on hover) so the context
    /// menu and a following drag can show them without waiting.
    func prefetchDropVerdicts(for itemID: String) {
        let key = "\(verdictRevision.uuidString)|\(itemID)"
        guard verdictCache[itemID] == nil, !prefetchingVerdicts.contains(key) else { return }
        prefetchingVerdicts.insert(key)
        Task { [weak self] in
            _ = await self?.loadDropVerdicts(for: itemID)
            self?.prefetchingVerdicts.remove(key)
        }
    }

    /// Adds an empty semester to the active pathway in calendar order. No-op
    /// when the pathway already has it.
    func addSemester(_ id: SemesterIdentity) {
        recordScheduleChange(actionName: "Add \(id.displayName)", message: "Added \(id.displayName)") {
            guard let pathwayIndex = activePathwayIndex,
                  !plan.pathways[pathwayIndex].semesters.contains(where: { $0.id == id })
            else { return }
            var pathway = plan.pathways[pathwayIndex]
            pathway.semesters.append(SemesterPlan(id: id, courseIDs: []))
            pathway.semesters.sort { $0.id < $1.id }
            plan.pathways[pathwayIndex] = pathway
            autosave()
        }
    }

    /// Only empty semesters can be deleted (a placeholder counts as content),
    /// and a pathway always keeps at least one semester.
    func canDeleteSemester(_ id: SemesterIdentity) -> Bool {
        guard let semesters = activePathway?.semesters, semesters.count > 1,
              let semester = semesters.first(where: { $0.id == id })
        else { return false }
        return semester.courseIDs.isEmpty
    }

    /// Deletes an empty semester and any kept load warnings for it, so a
    /// semester added back later starts clean.
    func deleteSemester(_ id: SemesterIdentity) {
        guard canDeleteSemester(id) else { return }
        recordScheduleChange(actionName: "Delete \(id.displayName)", message: "Deleted \(id.displayName)") {
            guard let pathwayIndex = activePathwayIndex else { return }
            var updated = plan
            updated.pathways[pathwayIndex].semesters.removeAll { $0.id == id }
            updated.overrides.removeAll { $0.courseID == ConflictWarning.semesterSubjectID && $0.semester == id }
            plan = updated
            autosave()
        }
    }

    /// Moves (or adds) a course or placeholder into `semester`. `index` is the
    /// position within the target semester after the item has been removed
    /// from its current spot; nil appends. Dropping an item back onto its own
    /// slot leaves the plan untouched.
    func moveCourse(_ courseID: String, to semester: SemesterIdentity, at index: Int? = nil) {
        let origin = activePathway?.semesters.first { $0.courseIDs.contains(courseID) }?.id
        // A lecture and its lab travel together; name both in the toast.
        let name: String
        if origin == nil {
            let labs = labPairing?.labOptions(forLecture: courseID) ?? []
            let lab = labs.count == 1 ? scheduleItemName(labs[0]) : "a lab"
            name = labs.isEmpty ? scheduleItemName(courseID) : "\(scheduleItemName(courseID)) and \(lab)"
        } else {
            let partners = activePathway.map { labPairing?.partners(of: courseID, in: $0) ?? [] } ?? []
            name = ([courseID] + partners).map(scheduleItemName).joined(separator: " and ")
        }
        let actionName: String
        let message: String
        if origin == nil {
            actionName = "Add \(name)"
            message = "Added \(name) to \(semester.displayName)"
        } else if origin == semester {
            actionName = "Move \(name)"
            message = "Reordered \(name) in \(semester.displayName)"
        } else {
            actionName = "Move \(name)"
            message = "Moved \(name) to \(semester.displayName)"
        }
        recordScheduleChange(actionName: actionName, message: message) {
            applyMove(courseID, to: semester, at: index)
        }
    }

    private func applyMove(_ courseID: String, to semester: SemesterIdentity, at index: Int?) {
        guard let pathwayIndex = activePathwayIndex else { return }
        let original = plan.pathways[pathwayIndex]
        let isNew = !original.semesters.contains { $0.courseIDs.contains(courseID) }
        var pathway: Pathway
        if let labPairing {
            // Moves the item's lab or lecture along; a newly added lecture
            // gets its lab beside it.
            pathway = labPairing.moving(courseID, to: semester, at: index, in: original)
            if isNew {
                pathway = labPairing.addingLab(for: courseID, in: semester, to: pathway)
            }
        } else {
            pathway = LabPairing.moving([courseID], to: semester, at: index, in: original)
        }
        guard pathway != original else { return }
        plan.pathways[pathwayIndex] = pathway
        autosave()
    }

    func removeCourse(_ courseID: String) {
        let name = ([courseID] + removalPartners(of: courseID)).map(scheduleItemName).joined(separator: " and ")
        recordScheduleChange(actionName: "Remove \(name)", message: "Removed \(name)") {
            applyRemove(courseID)
        }
    }

    /// A lecture's lab in the same semester goes with it. A lab removed on
    /// its own leaves its lecture (flagged until another lab is added).
    private func removalPartners(of courseID: String) -> [String] {
        guard let labPairing,
              let pathway = activePathway,
              !labPairing.labOptions(forLecture: courseID).isEmpty,
              let semester = pathway.semesters.first(where: { $0.courseIDs.contains(courseID) })
        else { return [] }
        return labPairing.partners(of: courseID, in: pathway).filter(semester.courseIDs.contains)
    }

    private func applyRemove(_ courseID: String) {
        guard let pathwayIndex = activePathwayIndex else { return }
        let partners = removalPartners(of: courseID)
        var pathway = plan.pathways[pathwayIndex]
        removeItem(courseID, from: &pathway, withLecture: false)
        for partner in partners {
            removeItem(partner, from: &pathway, withLecture: true)
        }
        plan.pathways[pathwayIndex] = pathway
        autosave()
    }

    /// Removes one schedule item. `withLecture` marks a lab leaving with its
    /// lecture: a lab placeholder, or a lab chosen from one, existed only
    /// for that lecture, so it's dropped rather than restored.
    private func removeItem(_ courseID: String, from pathway: inout Pathway, withLecture: Bool) {
        let resolvedFrom = pathway.resolvedPlaceholders.first(where: { $0.value == courseID })?.key
        let labPlaceholder = LabPairing.lecture(forLabPlaceholder: courseID) != nil ? courseID
            : resolvedFrom.flatMap { LabPairing.lecture(forLabPlaceholder: $0) != nil ? $0 : nil }
        if withLecture, let labPlaceholder {
            for index in pathway.semesters.indices {
                pathway.semesters[index].courseIDs.removeAll { $0 == courseID }
            }
            pathway.placeholders.removeValue(forKey: labPlaceholder)
            pathway.resolvedPlaceholders.removeValue(forKey: labPlaceholder)
            return
        }
        // If this course was previously resolved from a placeholder, swap
        // the placeholder slot back into the same semester instead of
        // leaving an empty hole.
        if let placeholderID = resolvedFrom {
            for index in pathway.semesters.indices {
                pathway.semesters[index].courseIDs = pathway.semesters[index].courseIDs.map { id in
                    id == courseID ? placeholderID : id
                }
            }
            pathway.resolvedPlaceholders.removeValue(forKey: placeholderID)
            // Pathways resolved before specs were kept around have no
            // PlaceholderSpec left for this slot; without one the schedule
            // board can't render the restored chip. Rebuild a minimal spec —
            // open-elective slots take any course, so an empty alternates
            // sentinel is fully faithful. Other categories fall back to the
            // full-catalog sentinel too rather than losing the slot.
            if pathway.placeholders[placeholderID] == nil {
                let credits = catalog?.coursesByID[courseID]?.credits ?? 3
                // Placeholder ids are "__pl::<categoryID>::<optionIndex>".
                let categoryID = placeholderID
                    .dropFirst(PathwayPlaceholder.prefix.count)
                    .components(separatedBy: "::")
                    .first ?? ScheduleGenerator.openElectiveCategoryID
                let isOpenElective = categoryID == ScheduleGenerator.openElectiveCategoryID
                pathway.placeholders[placeholderID] = PlaceholderSpec(
                    categoryID: categoryID,
                    categoryName: isOpenElective ? "Open Elective" : "Choose a course",
                    alternates: [],
                    credits: credits
                )
            }
        } else {
            for index in pathway.semesters.indices {
                pathway.semesters[index].courseIDs.removeAll { $0 == courseID }
            }
        }
    }

    func override(_ warning: ConflictWarning) {
        // A pending prerequisite choice is an explanation, not a conflict
        // to keep.
        guard canEditSchedule, warning.kind != .pendingPrerequisiteChoice else { return }
        let override = ConflictOverride(courseID: warning.courseID, semester: warning.semester, kind: warning.kind)
        if !plan.overrides.contains(override) {
            plan.overrides.append(override)
            autosave()
        }
    }

    func removeOverride(_ warning: ConflictWarning) {
        guard canEditSchedule else { return }
        guard plan.overrides.contains(where: { $0.courseID == warning.courseID && $0.semester == warning.semester && $0.kind == warning.kind }) else { return }
        plan.overrides.removeAll { $0.courseID == warning.courseID && $0.semester == warning.semester && $0.kind == warning.kind }
        autosave()
    }

    /// How many new warnings moving `courseID` to `semester` would add, from
    /// the cached drop verdicts; nil when they have not been computed.
    func newWarningCount(moving courseID: String, to semester: SemesterIdentity) -> Int? {
        cachedDropVerdicts(for: courseID)?[semester]?.newWarnings
            .filter { $0.kind.severity != .hidden && !$0.isOverridden }
            .count
    }

    func fixSuggestions(for warning: ConflictWarning) async -> [FixSuggestion] {
        guard !warning.isSemesterLevel, let catalog else { return [] }
        guard let verdicts = await loadDropVerdicts(for: warning.courseID),
              let pathway = activePathway,
              warnings.contains(where: { $0.id == warning.id })
        else { return [] }
        return FixSuggester(catalog: catalog).suggestions(for: warning, verdicts: verdicts, in: pathway)
    }

    func showCourse(_ courseID: String) {
        guard let course = catalog?.coursesByID[courseID] else { return }
        selectedCourse = course
        courseDetail = nil
        if let cached = courseDetailCache[courseID] {
            courseDetail = cached
            return
        }
        Task {
            var detail = await detailService.detail(for: course)
            courseDetail = detail

            // If the cached catalog doesn't carry a description for this course,
            // try a live fetch against JMU's course search page. Updates the
            // sheet in place when it succeeds and persists into the in-memory
            // catalog so subsequent clicks during this session skip the network.
            if detail.description == nil,
               let live = await detailService.liveDescription(for: course) {
                detail.description = live.description
                detail.descriptionStatus = detailService.descriptionStatus(forLiveFetched: live.sourceURL)
                persistLiveDescription(courseID: courseID, description: live.description, sourceURL: live.sourceURL)
            }

            courseDetailCache[courseID] = detail
            courseDetail = detail
        }
    }

    private func persistLiveDescription(courseID: String, description: String, sourceURL: URL) {
        guard var catalog else { return }
        guard let index = catalog.courses.firstIndex(where: { $0.id == courseID }) else { return }
        var course = catalog.courses[index]
        course.description = description
        course.descriptionSourceURL = sourceURL
        course.detailRetrievedAt = Date()
        catalog.courses[index] = course
        self.catalog = catalog
    }

    func saveCurrentPlan() {
        plan.updatedAt = Date()
        if plan.name == "My JMU Plan" {
            plan.name = activeProgram?.title ?? "My JMU Plan"
        }
        do {
            try save(plan)
            savedPlans = try loadPlans()
            statusMessage = "Plan saved."
        } catch {
            errorMessage = "The plan could not be saved: \(error.localizedDescription)"
        }
    }

    func startFresh() {
        clearScheduleHistory()
        plan = SavedStudentPlan()
        setupSheetPresented = true
        autosave()
    }

    func resume(_ saved: SavedStudentPlan) {
        clearScheduleHistory()
        plan = saved
        validateSelectedConcentration()
        statusMessage = "Resumed \(saved.name)."
    }

    func exportPDF() {
        guard let catalog, let activePathway else { return }
        do {
            try ExportService().exportPDF(planName: plan.name, pathway: activePathway, catalog: catalog, history: effectiveAcademicHistory)
        } catch {
            errorMessage = "PDF export failed: \(error.localizedDescription)"
        }
    }

    func exportICS() {
        guard let catalog, let activePathway else { return }
        do {
            try ExportService().exportICS(planName: plan.name, pathway: activePathway, catalog: catalog)
        } catch {
            errorMessage = "Calendar export failed: \(error.localizedDescription)"
        }
    }

    func resetAppData() {
        do {
            Self.flushPendingAutosaves()
            try catalogRepository.resetAppData()
            clearScheduleHistory()
            plan = SavedStudentPlan()
            savedPlans = []
            statusMessage = "App data cleared. Loading the bundled catalog..."
            errorMessage = nil
            Task { await load() }
        } catch {
            errorMessage = "App data could not be cleared: \(error.localizedDescription)"
        }
    }

    func refreshCatalog() {
        isRefreshingCatalog = true
        statusMessage = "Fetching JMU catalog HTML requirements..."
        Task {
            do {
                let refreshed = try await catalogRepository.refreshCatalogFromHTML { progress in
                    self.statusMessage = "Parsing \(progress.current) of \(progress.total): \(progress.programTitle)"
                }
                catalog = refreshed
                validateSelectedConcentration()
                isRefreshingCatalog = false
                let majors = refreshed.programs.filter { $0.kind == .major && $0.requirementDataComplete }.count
                let minors = refreshed.programs.filter { $0.kind == .minor && $0.requirementDataComplete }.count
                statusMessage = "Catalog requirements refreshed from JMU HTML. \(majors) majors and \(minors) minors now have schedulable requirement rows."
            } catch {
                isRefreshingCatalog = false
                errorMessage = "Catalog HTML refresh failed. The app is still using cached data."
            }
        }
    }

    /// Lecture/lab pairs for the current catalog and program; nil before
    /// the catalog loads.
    private var labPairing: LabPairing? {
        catalog.map { LabPairing(catalog: $0, activeProgramTitle: effectiveActiveProgram?.title) }
    }

    private var activePathwayIndex: Int? {
        guard let activePathway else { return nil }
        return plan.pathways.firstIndex(where: { $0.id == activePathway.id })
    }

    private func validateSelectedConcentration() {
        guard let activeProgram else { return }
        if activeProgram.concentrations.isEmpty {
            plan.concentrationID = nil
            return
        }
        if !activeProgram.concentrationSelectionRequired, plan.concentrationID == nil {
            return
        }
        guard let concentrationID = plan.concentrationID,
              activeProgram.concentrations.contains(where: { $0.id == concentrationID })
        else {
            plan.concentrationID = nil
            plan.pathways = []
            plan.activePathwayID = nil
            clearScheduleHistory()
            return
        }
    }

    /// Serial queue for autosave disk writes. Autosave runs on nearly every
    /// edit, so the write happens off the main thread and `savedPlans` is
    /// updated in memory instead of re-reading every plan file from disk.
    private nonisolated static let autosaveQueue = DispatchQueue(label: "edu.jmu.courseplanner.autosave", qos: .utility)

    /// Blocks until queued autosave writes reach disk. Called on quit.
    nonisolated static func flushPendingAutosaves() {
        autosaveQueue.sync {}
    }

    private func autosave() {
        var autosaved = plan
        autosaved.name = "Autosave"
        autosaved.updatedAt = Date()
        if let url = try? planURL(for: autosaved), let data = try? encodedPlan(autosaved) {
            Self.autosaveQueue.async { try? data.write(to: url, options: .atomic) }
        }
        if let index = savedPlans.firstIndex(where: { $0.id == autosaved.id }) {
            savedPlans[index] = autosaved
        } else {
            savedPlans.append(autosaved)
        }
        savedPlans.sort { $0.updatedAt > $1.updatedAt }
    }

    private func plansDirectory() throws -> URL {
        let directory = try storageDirectory ?? catalogRepository.supportDirectory().appending(path: "Plans", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func save(_ savedPlan: SavedStudentPlan) throws {
        // Autosave shares this plan's file; let queued writes land first so
        // they cannot overwrite this one.
        Self.flushPendingAutosaves()
        try encodedPlan(savedPlan).write(to: planURL(for: savedPlan), options: .atomic)
    }

    private func planURL(for savedPlan: SavedStudentPlan) throws -> URL {
        try plansDirectory().appending(path: "\(savedPlan.id.uuidString).jmuplan.json")
    }

    private func encodedPlan(_ savedPlan: SavedStudentPlan) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(savedPlan)
    }

    private func loadPlans() throws -> [SavedStudentPlan] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let urls = try FileManager.default.contentsOfDirectory(at: plansDirectory(), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(SavedStudentPlan.self, from: data)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }
}

/// Snapshot of in-flight pathway generation shown by the modal overlay.
struct ScheduleGenerationProgress: Equatable, Sendable {
    var current: Int
    var total: Int
    var pathwayName: String
}
