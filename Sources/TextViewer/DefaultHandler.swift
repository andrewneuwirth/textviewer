import AppKit
import UniformTypeIdentifiers

/// Asking LaunchServices to make this app the default has to come from the app
/// itself — the same request from a command-line tool is accepted and then
/// quietly ignored. macOS may show a confirmation dialog, which is the point:
/// changing a default is the user's call.
enum DefaultHandler {
    static let contentTypes = ["public.json", "public.plain-text", "public.log"]

    @discardableResult
    static func claimDefaults() async -> [String] {
        let app = Bundle.main.bundleURL
        var results: [String] = []
        for identifier in contentTypes {
            guard let type = UTType(identifier) else { continue }
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type)
                results.append("set    \(identifier)")
            } catch {
                results.append("failed \(identifier): \(error.localizedDescription)")
            }
        }
        return results
    }

    /// Reports what LaunchServices currently resolves each type to.
    static func currentHandlers() -> [String] {
        contentTypes.compactMap { identifier in
            guard let type = UTType(identifier) else { return nil }
            let handler = NSWorkspace.shared.urlForApplication(toOpen: type)?.lastPathComponent ?? "none"
            return "\(identifier) -> \(handler)"
        }
    }
}
