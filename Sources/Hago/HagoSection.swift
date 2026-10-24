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

    static let primarySections: [Self] = [.overview, .review, .activity, .reports]
    static let settingsSections: [Self] = [.tracking, .rules, .privacy, .aiReview, .projects, .categories]

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .tracking:
            "General"
        case .overview:
            "Overview"
        case .reports:
            "Reports"
        case .review:
            "Review"
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
        case .tracking:
            "gearshape"
        case .overview:
            "chart.bar.xaxis"
        case .reports:
            "chart.xyaxis.line"
        case .review:
            "tray.full"
        case .aiReview:
            "sparkles"
        case .activity:
            "clock.arrow.circlepath"
        case .rules:
            "list.bullet.rectangle"
        case .projects:
            "folder"
        case .categories:
            "tag"
        case .privacy:
            "hand.raised"
        }
    }
}
