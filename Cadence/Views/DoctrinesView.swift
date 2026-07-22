import SwiftUI

/// Placeholder — doctrines/knowledge base is not part of the file-based build yet.
struct DoctrinesView: View {
    var body: some View {
        ComingSoonView(
            icon: "book.closed",
            title: "Doctrines",
            message: "A place for saved findings and lessons. Coming soon."
        )
    }
}

/// Shared "coming soon" placeholder for parked features.
struct ComingSoonView: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(DS.textTertiary)
            Text(title).font(DS.Font.displayL)
            Text(message).font(DS.Font.body).foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.contentBG)
    }
}
