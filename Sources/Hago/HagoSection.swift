import SwiftUI

enum HagoSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case reports
    case review
    case aiReview
    case activity
    case rules
    case projects
    case categories
    case privacy

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .overview:
            "Overview"
        case .reports:
            "Reports"
        case .review:
            "Review"
        case .aiReview:
            "AI Harness"
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
