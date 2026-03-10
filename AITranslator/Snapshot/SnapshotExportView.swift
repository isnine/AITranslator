#if os(macOS)
import SwiftUI

/// Minimal, dependency-light view for validating offscreen snapshot export pipeline.
///
/// Once this works reliably, we can swap its body to real app screens.
struct SnapshotExportView: View {
    let title: String

    var body: some View {
        ZStack {
            Color.white
            VStack(spacing: 16) {
                Text("TLingo macOS Snapshot")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.black)
                Text(title)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.gray)
            }
            .padding(40)
        }
    }
}
#endif
