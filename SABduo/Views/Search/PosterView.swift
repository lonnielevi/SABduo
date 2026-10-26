import SwiftUI

/// Tries each poster URL in turn and appears only once one loads, so a missing cover never
/// shows a placeholder that then collapses and shifts the page. Tap to enlarge.
struct PosterView: View {
    let urls: [URL]
    var width: CGFloat = 110
    @State private var poster: (url: URL, image: UIImage)?
    @State private var showingFullSize = false

    var body: some View {
        // A ZStack rather than a Group: an empty Group has no view to run the task on.
        ZStack {
            if let poster {
                Image(uiImage: poster.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 8))
                    .shadow(radius: 4, y: 2)
                    .frame(width: width)
                    .onTapGesture { showingFullSize = true }
                    .accessibilityLabel("Poster")
                    .accessibilityAddTraits(.isButton)
                    .transition(.opacity)
                    .sheet(isPresented: $showingFullSize) {
                        FullSizePoster(url: poster.url)
                    }
            }
        }
        .task(id: urls) { await load() }
    }

    private func load() async {
        // Details can add candidates; keep a poster that already loaded if it's still one of them.
        if let poster, urls.contains(poster.url) { return }
        for url in urls {
            // Not every release has a cover on every indexer; fall through to the next candidate.
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                  let image = UIImage(data: data) else { continue }
            withAnimation { poster = (url, image) }
            return
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
