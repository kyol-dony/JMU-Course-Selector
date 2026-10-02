import PlannerCore

enum TranscriptTestFixtures {
    static func sampleText() -> String {
        """
        James Madison University
        Unofficial Transcript
        Academic Program
        Computer Info Systems - BBA Major
        Statistics - BS Major
        Beginning of Undergraduate Record
        Fall Semester 2026
        Course Description Attempted Earned Grade Points
        ECON 200 INTRODUCTION TO MACROECON 3.00 0.00 0.000
        MATH 236 CALCULUS II 4.00 0.00 0.000
        MATH 321 ANALYSIS VAR & EXPER DESIGN 3.00 0.00 0.000
        MATH 325 SURVEY SAMPLING METHODS 3.00 0.00 0.000
        MUS 200 MUSIC AND CULTURE 3.00 0.00 0.000
        Test Credits Applied Toward Undergraduate
        Course Description Attempted Earned Grade Points
        CHEM 131 GENERAL CHEMISTRY I 0.00 3.00 CR 0.000
        CHEM 132L GENERAL CHEMISTRY LAB 0.00 1.00 CR 0.000
        CHEM 131L GENERAL CHEMISTRY LAB 0.00 1.00 CR 0.000
        CHEM 132 GENERAL CHEMISTRY II 0.00 3.00 CR 0.000
        CS OOO GENERAL CS CREDIT 0.00 3.00 CR 0.000
        GEOG 200 GEOGRAPHY: GLOBAL DIMENSION 0.00 3.00 CR 0.000
        GNED 123 GENERAL EDUCATION C2L 0.00 3.00 CR 0.000
        HIST 102 WORLD HISTORY SINCE 1500 0.00 3.00 CR 0.000
        HIST 225 U.S. HISTORY 0.00 4.00 CR 0.000
        MATH 206 INTRODUCTORY CALCULUS II 0.00 3.00 CR 0.000
        MATH 235 CALCULUS I 0.00 4.00 CR 0.000
        MATH 220 ELEMENTARY STATISTICS 0.00 3.00 CR 0.000
        PHYS 240L UNIVERSITY PHYSICS LAB I 0.00 1.00 CR 0.000
        PHYS 240 UNIVERSITY PHYSICS I 0.00 3.00 CR 0.000
        PHYS 150L GENERAL PHYSICS LAB II 0.00 1.00 CR 0.000
        PHYS 150 COLLEGE PHYSICS II 0.00 3.00 CR 0.000
        PHYS 140 COLLEGE PHYSICS I 0.00 3.00 CR 0.000
        PHYS 140L GENERAL PHYSICS LAB I 0.00 1.00 CR 0.000
        WRTC 103 RHETORICAL READING AND WRITING 0.00 3.00 CR 0.000
        Test Trans GPA: 0.000 Transfer Totals: 0.00 49.00 0.000
        Term GPA 0.000 Term Totals 16.00 0.00 0.000
        Cum GPA 0.000 Cum Totals 0.00 49.00 0.000
        End of Unofficial Transcript
        """
    }
    static func prerequisiteCatalog() -> Catalog {
        Catalog.fixture(courses: [
            Course(id: "CS149", code: "CS 149", title: "Programming", credits: 3, availability: [.fall, .spring], prerequisites: []),
            Course(id: "CS159", code: "CS 159", title: "Advanced Programming", credits: 3, availability: [.fall, .spring], prerequisites: ["CS149"])
        ], program: Program.fixture(id: "cs", title: "CS", requirements: [RequirementCategory(id: "core", name: "Core", requiredCredits: 6, courseOptions: [["CS149"], ["CS159"]])]))
    }
    static func sampleCatalog() -> Catalog { prerequisiteCatalog() }
    static func degreeCatalog() -> Catalog {
        let courses = (1...30).map { Course(id: "REQ\($0)", code: "REQ \($0)", title: "Required \($0)", credits: 3, availability: [.fall, .spring], prerequisites: []) }
        return Catalog.fixture(courses: courses, program: Program.fixture(id: "degree", title: "Degree", requirements: [RequirementCategory(id: "core", name: "Core", requiredCredits: 90, courseOptions: courses.map { [$0.id] })]))
    }
}
