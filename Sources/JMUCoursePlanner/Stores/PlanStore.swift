import AppKit
import Foundation
import PlannerCore
import SwiftUI

@MainActor
final class PlanStore: ObservableObject {
    @Published var catalog: Catalog?
    @Published var plan = SavedStudentPlan()
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

    private let catalogRepository = CatalogRepository()
    private let detailService = CourseDetailService()
    private var courseDetailCache: [String: CourseDetail] = [:]

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
        return !activeProgram.concentrations.isEmpty
    }

    var majorSelectionComplete: Bool {
        guard let activeProgram else { return false }
        guard !activeProgram.concentrations.isEmpty else { return true }
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
        guard let catalog, let activePathway else { return [] }
        return ConflictDetector(catalog: catalog).warnings(for: activePathway, overrides: plan.overrides)
    }

    var progress: GraduationProgress? {
        guard let catalog, let programID = plan.programID, let activePathway else { return nil }
        return try? ProgressCalculator(catalog: catalog).progress(
            programID: programID,
            concentrationID: plan.concentrationID,
            pathway: activePathway,
            transferCredits: plan.transferCredits,
            additionalPrograms: selectedMinorPrograms()
        )
    }

    /// Effective Program for each added minor (parent program + its selected
    /// concentration's requirements merged). Used to thread minor requirements
    /// into schedule generation and progress tracking.
    func selectedMinorPrograms() -> [Program] {
        plan.minors.compactMap { effectiveMinorProgram(for: $0) }
    }

    /// Set of course IDs the student has completed (transfer credit + scheduled in active pathway).
    var completedCourseIDs: Set<String> {
        var ids = Set(plan.transferCredits.flatMap(\.courseIDs))
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
        if PathwayPlaceholder.isPlaceholder(id),
           let spec = activePathway?.placeholders[id] {
            return Course(
                id: id,
                code: "Choose course",
                title: spec.categoryName,
                credits: spec.credits,
                availability: nil,
                prerequisites: [],
                verificationStatus: .partial,
                registrarURL: nil
            )
        }
        return catalog?.coursesByID[id]
    }

    /// Replace a placeholder course in the active pathway with the chosen real
    /// course ID. Mutates the active pathway in place and drops the placeholder
    /// from the pathway's placeholders map.
    func resolvePlaceholder(_ placeholderID: String, with chosenCourseID: String) {
        guard let pathwayIndex = activePathwayIndex else { return }
        var pathway = plan.pathways[pathwayIndex]
        for semesterIndex in pathway.semesters.indices {
            pathway.semesters[semesterIndex].courseIDs = pathway.semesters[semesterIndex].courseIDs.map { id in
                id == placeholderID ? chosenCourseID : id
            }
        }
        pathway.placeholders.removeValue(forKey: placeholderID)
        plan.pathways[pathwayIndex] = pathway
        autosave()
    }

    func load() async {
        do {
            catalog = try catalogRepository.loadCatalog()
            savedPlans = try loadPlans()
            if let autosave = savedPlans.first(where: { $0.name == "Autosave" }) {
                plan = autosave
                validateSelectedConcentration()
            }
            statusMessage = "Catalog loaded from the 2025-2026 JMU undergraduate catalog cache."
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
        recomputeAPCredits()
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
        return try? program.effectiveProgram(concentrationID: selection.concentrationID)
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
        // Don't double-count an AP-awarded course against a dual-enrollment
        // entry for the same course: treat dual-enrollment course IDs as
        // already-completed when scoring AP variants.
        let dualEnrollmentCourses = Set(plan.transferCredits
            .filter { credit in !plan.apScores.contains(where: { credit.sourceDescription.contains("AP \($0.examName)") }) }
            .flatMap(\.courseIDs))
        let apCredits = TransferCreditMapper(catalog: catalog).credits(
            forAPScores: plan.apScores,
            program: effectiveActiveProgram,
            completedCourseIDs: dualEnrollmentCourses
        )
        // Replace only the AP-sourced credits; preserve any dual enrollment entries.
        let dualOnly = plan.transferCredits.filter { credit in
            !plan.apScores.contains(where: { credit.sourceDescription.contains("AP \($0.examName)") })
        }
        plan.transferCredits = apCredits + dualOnly
    }

    func addDualEnrollment(label: String, courseID: String, credits: Int) {
        plan.transferCredits.append(TransferCredit(sourceDescription: label, courseIDs: [courseID], credits: credits))
        autosave()
    }

    func generateSchedules() {
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

        do {
            plan.pathways = try ScheduleGenerator(catalog: catalog).generatePathways(
                for: programID,
                concentrationID: plan.concentrationID,
                workload: plan.workload,
                transferCredits: plan.transferCredits,
                starting: SemesterIdentity(year: 2026, term: .fall),
                additionalPrograms: selectedMinorPrograms()
            )
            plan.activePathwayID = plan.pathways.first?.id
            errorMessage = nil
            autosave()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveCourse(_ courseID: String, to semester: SemesterIdentity) {
        guard let pathwayIndex = activePathwayIndex else { return }
        var pathway = plan.pathways[pathwayIndex]
        for index in pathway.semesters.indices {
            pathway.semesters[index].courseIDs.removeAll { $0 == courseID }
        }
        if let target = pathway.semesters.firstIndex(where: { $0.id == semester }) {
            pathway.semesters[target].courseIDs.append(courseID)
        } else {
            pathway.semesters.append(SemesterPlan(id: semester, courseIDs: [courseID]))
            pathway.semesters.sort { $0.id < $1.id }
        }
        plan.pathways[pathwayIndex] = pathway
        autosave()
    }

    func removeCourse(_ courseID: String) {
        guard let pathwayIndex = activePathwayIndex else { return }
        for index in plan.pathways[pathwayIndex].semesters.indices {
            plan.pathways[pathwayIndex].semesters[index].courseIDs.removeAll { $0 == courseID }
        }
        autosave()
    }

    func override(_ warning: ConflictWarning) {
        let override = ConflictOverride(courseID: warning.courseID, semester: warning.semester, kind: warning.kind)
        if !plan.overrides.contains(override) {
            plan.overrides.append(override)
            autosave()
        }
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
            // try a live fetch against JMU's preview_course.php page. Updates the
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
        plan = SavedStudentPlan()
        autosave()
    }

    func resume(_ saved: SavedStudentPlan) {
        plan = saved
        validateSelectedConcentration()
        statusMessage = "Resumed \(saved.name)."
    }

    func exportPDF() {
        guard let catalog, let activePathway else { return }
        do {
            try ExportService().exportPDF(planName: plan.name, pathway: activePathway, catalog: catalog)
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
            try catalogRepository.resetAppData()
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
        guard let concentrationID = plan.concentrationID,
              activeProgram.concentrations.contains(where: { $0.id == concentrationID })
        else {
            plan.concentrationID = nil
            plan.pathways = []
            plan.activePathwayID = nil
            return
        }
    }

    private func autosave() {
        var autosaved = plan
        autosaved.name = "Autosave"
        autosaved.updatedAt = Date()
        try? save(autosaved)
        savedPlans = (try? loadPlans()) ?? savedPlans
    }

    private func plansDirectory() throws -> URL {
        let directory = try catalogRepository.supportDirectory().appending(path: "Plans", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func save(_ savedPlan: SavedStudentPlan) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = try plansDirectory().appending(path: "\(savedPlan.id.uuidString).jmuplan.json")
        try encoder.encode(savedPlan).write(to: url)
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
