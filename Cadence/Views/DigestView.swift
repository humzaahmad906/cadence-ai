import SwiftUI

/// Placeholder sheet — the daily standup digest is not part of the file-based build yet.
struct DigestView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily Digest").font(.title2.bold())
                Spacer()
                Button("Close") { dismiss() }
            }
            ComingSoonView(
                icon: "text.badge.checkmark",
                title: "Coming soon",
                message: "Auto-drafted standup updates will return in a future build."
            )
        }
        .padding()
        .frame(width: 640, height: 420)
    }
}
