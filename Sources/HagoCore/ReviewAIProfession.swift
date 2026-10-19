import Foundation

public enum ReviewAIProfession: String, CaseIterable, Codable, Identifiable, Sendable {
    case notSpecified
    case softwareDeveloper
    case designer
    case productManager
    case dataAnalyst
    case marketing
    case sales
    case businessOwner
    case writer
    case educator
    case researcher
    case healthcare
    case legal
    case finance
    case engineer
    case skilledTrades
    case operations
    case student
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .notSpecified: "Choose Profession"
        case .softwareDeveloper: "Software Developer"
        case .designer: "Designer"
        case .productManager: "Product or Project Manager"
        case .dataAnalyst: "Data Analyst or Scientist"
        case .marketing: "Marketing Professional"
        case .sales: "Sales Professional"
        case .businessOwner: "Business Owner"
        case .writer: "Writer or Editor"
        case .educator: "Teacher or Educator"
        case .researcher: "Researcher"
        case .healthcare: "Healthcare Professional"
        case .legal: "Legal Professional"
        case .finance: "Finance Professional"
        case .engineer: "Engineer"
        case .skilledTrades: "Skilled Tradesperson"
        case .operations: "Operations Professional"
        case .student: "Student"
        case .other: "Other"
        }
    }

    // This guidance belongs to the analysis prompt, not the settings interface.
    var reviewFocus: String {
        switch self {
        case .notSpecified, .other: "Use the activity evidence and established rule history to identify the user's professional activity."
        case .softwareDeveloper: "Software development, programming, debugging, testing, code review, architecture, technical research, and software delivery."
        case .designer: "Visual design, user experience, interaction design, prototyping, creative research, and design delivery."
        case .productManager: "Product strategy, customer research, requirements, planning, delivery coordination, and stakeholder communication."
        case .dataAnalyst: "Data analysis, statistics, data engineering, modeling, visualization, and reporting."
        case .marketing: "Market research, campaign planning, content strategy, advertising, brand management, and performance analysis."
        case .sales: "Prospecting, customer relationships, sales meetings, proposals, account management, and commercial negotiations."
        case .businessOwner: "Business strategy, operations, customer service, finance, hiring, and business administration."
        case .writer: "Research, writing, editing, publishing, content production, and editorial planning."
        case .educator: "Teaching, lesson preparation, assessment, student support, and educational administration."
        case .researcher: "Literature review, study design, experiments, analysis, academic writing, and research collaboration."
        case .healthcare: "Clinical practice, patient care coordination, medical research, professional learning, and healthcare administration."
        case .legal: "Legal research, case preparation, drafting, client work, compliance, and practice administration."
        case .finance: "Financial analysis, accounting, budgeting, auditing, client services, and financial reporting."
        case .engineer: "Engineering design, technical calculations, simulation, testing, project documentation, and technical delivery."
        case .skilledTrades: "Practical trade work, technical planning, materials, estimates, site coordination, and customer jobs."
        case .operations: "Operational planning, logistics, procurement, process improvement, service delivery, and team coordination."
        case .student: "Coursework, study, assignments, academic research, examinations, and educational projects."
        }
    }
}
