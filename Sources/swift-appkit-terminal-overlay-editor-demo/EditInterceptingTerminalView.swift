import Foundation
import SwiftTerm

@MainActor
final class EditInterceptingTerminalView: LocalProcessTerminalView {
    private static let editPrefix = "DemoEdit="

    var onEditRequest: ((URL) -> Void)?

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
        guard let payload = String(bytes: content, encoding: .utf8) else {
            return
        }

        guard payload.hasPrefix(Self.editPrefix) else {
            return
        }

        let path = String(payload.dropFirst(Self.editPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !path.isEmpty else {
            return
        }

        onEditRequest?(URL(fileURLWithPath: path))
    }
}
