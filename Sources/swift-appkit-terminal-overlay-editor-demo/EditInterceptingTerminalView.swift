import Foundation
import SwiftTerm

@MainActor
final class EditInterceptingTerminalView: LocalProcessTerminalView {
    private static let editPrefix = "DemoEdit="
    private static let oscPrefix = Data("\u{1B}]1337;\(editPrefix)".utf8)
    private static let oscSuffix = UInt8(0x07)

    var onEditRequest: ((URL) -> Void)?
    private var pendingHostOutput = Data()

    override func dataReceived(slice: ArraySlice<UInt8>) {
        pendingHostOutput.append(contentsOf: slice)

        while let range = pendingHostOutput.range(of: Self.oscPrefix) {
            let suffixSearchRange = range.upperBound..<pendingHostOutput.endIndex
            guard let suffixIndex = pendingHostOutput[suffixSearchRange].firstIndex(of: Self.oscSuffix) else {
                break
            }

            let payloadData = pendingHostOutput[range.upperBound..<suffixIndex]
            if let path = String(data: payloadData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                onEditRequest?(URL(fileURLWithPath: path))
            }

            pendingHostOutput.removeSubrange(range.lowerBound...suffixIndex)
        }

        if pendingHostOutput.count > 4096 {
            pendingHostOutput.removeAll(keepingCapacity: true)
        }

        super.dataReceived(slice: slice)
    }
}
