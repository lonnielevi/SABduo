import SwiftUI

/// Tries each poster URL in turn; takes no space if none of them load. Tap to enlarge.
struct PosterView: View {
    let urls: [URL]
    var width: CGFloat = 110
    @State private var index = 0
    @State private var showingFullSize = false

    var body: some View {
        if index < urls.count {
            let url = urls[index]
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 8))
                        .shadow(radius: 4, y: 2)
                        .frame(width: width)
                        .onTapGesture { showingFullSize = true }
                        .accessibilityLabel("Poster")
                        .accessibilityAddTraits(.isButton)
                case .failure:
                    // Not every release has a cover on every indexer; fall through to the next candidate.
                    Color.clear
                        .frame(width: 0, height: 0)
                        .onAppear { index += 1 }
                default:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .frame(width: width)
                        .overlay { ProgressView() }
                }
            }
            .id(url)
            .sheet(isPresented: $showingFullSize) {
                FullSizePoster(url: url)
            }
        }
    }
}

private struct FullSizePoster: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        NavigationStack {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                ProgressView()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
