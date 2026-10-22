import SwiftUI

enum HagoSection: String, CaseIterable, Identifiable, Hashable {
    case tracking
    case profile
    case overview
    case reports
    case review
    case aiReview
    case activity
    case rules
    case projects
    case categories
    case privacy

    static let dashboardSections: [Self] = [.overview, .reports, .review, .activity]
    static let settingsSections: [Self] = [.tracking, .profile, .rules, .projects, .categories, .privacy, .aiReview]

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .tracking: "Tracking & Updates"
        case .profile: "Work Profile"
        case .overview:
            "Overview"
        case .reports:
            "Reports"
        case .review:
            "Needs Review"
        case .aiReview:
            "AI Suggestions"
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
        case .profile: "person.crop.circle"
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
