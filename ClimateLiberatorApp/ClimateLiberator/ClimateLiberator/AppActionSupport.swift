import Foundation
import AppKit

struct ActionAvailability {
    let isEnabled: Bool
    let reason: String?

    static let ready = ActionAvailability(isEnabled: true, reason: nil)

    static func unavailable(_ reason: String) -> ActionAvailability {
        ActionAvailability(isEnabled: false, reason: reason)
    }
}

enum PathExpectation {
    case file
    case directory
    case any
}

enum AppActionSupport {
    static func pathAvailability(path: String,
                                 expectation: PathExpectation,
                                 emptyReason: String,
                                 missingReason: String? = nil) -> ActionAvailability {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .unavailable(emptyReason)
        }

        let resolved = NSString(string: trimmed).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDirectory) else {
            return .unavailable(missingReason ?? emptyReason)
        }

        switch expectation {
        case .file:
            return isDirectory.boolValue ? .unavailable(missingReason ?? "Expected a file, but found a folder.") : .ready
        case .directory:
            return isDirectory.boolValue ? .ready : .unavailable(missingReason ?? "Expected a folder, but found a file.")
        case .any:
            return .ready
        }
    }

    @discardableResult
    static func openExistingPath(_ path: String,
                                 expectation: PathExpectation = .any) -> Bool {
        let availability = pathAvailability(
            path: path,
            expectation: expectation,
            emptyReason: "Path is not configured.",
            missingReason: "Path does not exist."
        )
        guard availability.isEnabled else { return false }
        let resolved = NSString(string: path).expandingTildeInPath
        return NSWorkspace.shared.open(URL(fileURLWithPath: resolved))
    }
}
