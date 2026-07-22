import Foundation

enum AppEnvironment {
    static let apiBaseURL = URL(string: "https://cineviet.live/api")!
    static let siteBaseURL = URL(string: "https://cineviet.live")!
    static let mobileKey = "cineviet-mobile-app-v2"
    static let userAgent = "CineVietIOS/1.0"
    static let googleClientID = "186784861581-mc6buqlfpbrprko3iqfp6fi0biqc3o3s.apps.googleusercontent.com"
    static let googleServerClientID = "186784861581-5l7skrrke87pmf669l6ach0brbra4v76.apps.googleusercontent.com"

    static let connectTimeout: TimeInterval = 12
    static let resourceTimeout: TimeInterval = 25
}
