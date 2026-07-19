import Foundation

enum AppEnvironment {
    static let apiBaseURL = URL(string: "https://cineviet.live/api")!
    static let siteBaseURL = URL(string: "https://cineviet.live")!
    static let mobileKey = "cineviet-mobile-app-v2"
    static let userAgent = "CineVietIOS/1.0"

    static let connectTimeout: TimeInterval = 12
    static let resourceTimeout: TimeInterval = 25
}
