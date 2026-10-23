import SwiftUI

enum HagoSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case reports
    case review
    case activity
    case tracking
    case rules
    case projects
    case categories
    case privacy
    case aiReview

    static let primarySections: [Self] = [.overview, .reports, .review, .activity, .tracking, .rules, .privacy, .aiReview]
    static let advancedSections: [Self] = [.projects, .categories]

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .tracking: "Tracking & Updates"
        case .overview:
            "Overview"
        case .reports:
            "Reports"
        case .review:
            "Needs review"
        case .aiReview:
            "AI suggestions"
        case .activity:
            "Activity"
        case .rules:
            "Rules"
        case .projects:
            "Projects"
        case .categories:
            "Categories"
        case .privacy:
            "Privacy"
        }
    }

    var symbolName: String {
        switch self {
        case .tracking: "gearshape"
        case .overview:
            "chart.bar.xaxis"
        case .reports:
            "chart.xyaxis.line"
        case .review:
            "checklist"
        case .aiReview:
            "cpu"
        case .activity:
            "clock.arrow.circlepath"
        case .rules:
            "line.3.horizontal.decrease.circle"
        case .projects:
            "folder"
        case .categories:
            "tag"
        case .privacy:
            "eye.slash"
        }
    }
}
