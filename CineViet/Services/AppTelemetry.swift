import Foundation
import os

/// Dependency-free telemetry boundary. A Firebase/other adapter can be installed
/// by the composition root without making analytics a launch requirement.
protocol TelemetrySink { func event(_ name: String, parameters: [String: String]); func error(_ error: Error, context: String) }

final class AppTelemetry {
    static let shared = AppTelemetry()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "live.cineviet", category: "telemetry")
    var sink: TelemetrySink?
    func event(_ name: String, parameters: [String: String] = [:]) { logger.info("event=\(name, privacy: .public)"); sink?.event(name, parameters: parameters) }
    func record(error: Error, context: String) { logger.error("context=\(context, privacy: .public) error=\(error.localizedDescription, privacy: .private)"); sink?.error(error, context: context) }
}
