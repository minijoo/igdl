import SwiftUI

struct VideoRow: View {
    let video: Video

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(video.username)
                    .font(.subheadline).bold()
                Spacer()
                Text(video.shortCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let caption = video.captionText, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
