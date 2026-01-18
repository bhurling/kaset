import SwiftUI

// MARK: - HomeSectionItemCard

/// Reusable card view for home section items (songs, playlists, albums, artists).
@available(macOS 26.0, *)
struct HomeSectionItemCard: View {
    let item: HomeSectionItem
    let rank: Int?
    let action: () -> Void

    /// Card dimensions.
    private static let cardWidth: CGFloat = 160
    private static let cardHeight: CGFloat = 160

    /// Hover state for play overlay.
    @State private var isHovering = false

    init(item: HomeSectionItem, rank: Int? = nil, action: @escaping () -> Void) {
        self.item = item
        self.rank = rank
        self.action = action
    }

    var body: some View {
        Button(action: self.action) {
            if let rank {
                self.chartContent(rank: rank)
            } else {
                self.regularContent
            }
        }
        .buttonStyle(.interactiveCard)
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                self.isHovering = hovering
            }
        }
    }

    // MARK: - Regular Card Content

    private var regularContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            self.thumbnail
            self.titleAndSubtitle
        }
    }

    // MARK: - Chart Card Content

    private func chartContent(rank: Int) -> some View {
        ZStack(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 8) {
                self.thumbnail
                self.titleAndSubtitle
            }

            // Rank badge overlay with adaptive styling
            Text("\(rank)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .shadow(color: Color(nsColor: .windowBackgroundColor).opacity(0.8), radius: 4, x: 0, y: 1)
                .padding(.leading, 8)
                .padding(.bottom, 60)
        }
    }

    // MARK: - Shared Components

    private var thumbnail: some View {
        ZStack {
            if let url = self.item.thumbnailURL?.highQualityThumbnailURL {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    self.placeholderView
                }
            } else {
                self.placeholderView
            }
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(.rect(cornerRadius: 8))
    }

    /// Placeholder view for items without thumbnails.
    /// Uses the API-provided color for mood/genre cards, or a gradient based on the title.
    private var placeholderView: some View {
        let gradient = self.gradientForItem
        return Rectangle()
            .fill(gradient)
            .overlay {
                // Show a contextual icon based on item type
                Image(systemName: self.placeholderIcon)
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.8))
            }
    }

    /// Returns appropriate icon for the placeholder based on item type.
    private var placeholderIcon: String {
        switch self.item {
        case .song: "music.note"
        case .album: "square.stack"
        case .playlist: "music.note.list"
        case .artist: "person.fill"
        }
    }

    /// Generates a gradient for the card.
    /// Uses API-provided color (from description) for mood cards, or title-based hash.
    private var gradientForItem: LinearGradient {
        // Check if this is a mood card with color in description
        if case let .playlist(playlist) = item,
           let colorHex = playlist.description,
           colorHex.hasPrefix("#"),
           let color = Color(hex: colorHex)
        {
            // Create a gradient from the API color
            return LinearGradient(
                colors: [color, color.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        // Fallback to title-based gradient
        return Self.gradientForTitle(self.item.title)
    }

    /// Generates a consistent gradient color based on the title string.
    private static func gradientForTitle(_ title: String) -> LinearGradient {
        let hash = abs(title.hashValue)
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = (hue1 + 0.1).truncatingRemainder(dividingBy: 1.0)

        let color1 = Color(hue: hue1, saturation: 0.6, brightness: 0.5)
        let color2 = Color(hue: hue2, saturation: 0.7, brightness: 0.35)

        return LinearGradient(
            colors: [color1, color2],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var titleAndSubtitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(self.item.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: Self.cardWidth, alignment: .leading)

            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: Self.cardWidth, alignment: .leading)
            }
        }
    }
}

// MARK: - HomeSectionItemContextMenu

/// Reusable context menu for HomeSectionItem (songs, albums, playlists, artists).
/// Provides consistent context menu behavior across Home, Explore, Charts, and New Releases views.
@available(macOS 26.0, *)
@MainActor
enum HomeSectionItemContextMenu {
    /// Creates a complete context menu for a HomeSectionItem.
    @ViewBuilder
    static func menu(
        for item: HomeSectionItem,
        playerService: PlayerService,
        favoritesManager: FavoritesManager,
        likeStatusManager: SongLikeStatusManager,
        onNavigateToPlaylist: @escaping (Playlist) -> Void,
        onNavigateToArtist: @escaping (Artist) -> Void
    ) -> some View {
        switch item {
        case let .song(song):
            Self.songMenu(
                song: song,
                playerService: playerService,
                favoritesManager: favoritesManager,
                likeStatusManager: likeStatusManager,
                onNavigateToPlaylist: onNavigateToPlaylist,
                onNavigateToArtist: onNavigateToArtist
            )

        case let .album(album):
            Self.albumMenu(
                album: album,
                favoritesManager: favoritesManager,
                onNavigateToPlaylist: onNavigateToPlaylist
            )

        case let .playlist(playlist):
            Self.playlistMenu(
                playlist: playlist,
                favoritesManager: favoritesManager,
                onNavigateToPlaylist: onNavigateToPlaylist
            )

        case let .artist(artist):
            Self.artistMenu(
                artist: artist,
                favoritesManager: favoritesManager,
                onNavigateToArtist: onNavigateToArtist
            )
        }
    }

    // MARK: - Song Menu

    @ViewBuilder
    private static func songMenu(
        song: Song,
        playerService: PlayerService,
        favoritesManager: FavoritesManager,
        likeStatusManager: SongLikeStatusManager,
        onNavigateToPlaylist: @escaping (Playlist) -> Void,
        onNavigateToArtist: @escaping (Artist) -> Void
    ) -> some View {
        Button {
            playerService.insertNextInQueue([song])
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }

        Button {
            playerService.appendToQueue([song])
        } label: {
            Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward")
        }

        Divider()

        FavoritesContextMenu.menuItem(for: song, manager: favoritesManager)

        Divider()

        LikeDislikeContextMenu(song: song, likeStatusManager: likeStatusManager)

        Divider()

        ShareContextMenu.menuItem(for: song)

        Divider()

        if let artist = song.artists.first, !artist.id.isEmpty, !artist.id.contains("-") {
            Button {
                onNavigateToArtist(artist)
            } label: {
                Label("Go to Artist", systemImage: "person")
            }
        }

        if let album = song.album, album.hasNavigableId {
            let playlist = Playlist(
                id: album.id,
                title: album.title,
                description: nil,
                thumbnailURL: album.thumbnailURL ?? song.thumbnailURL,
                trackCount: album.trackCount,
                author: album.artistsDisplay
            )
            Button {
                onNavigateToPlaylist(playlist)
            } label: {
                Label("Go to Album", systemImage: "square.stack")
            }
        }
    }

    // MARK: - Album Menu

    @ViewBuilder
    private static func albumMenu(
        album: Album,
        favoritesManager: FavoritesManager,
        onNavigateToPlaylist: @escaping (Playlist) -> Void
    ) -> some View {
        Button {
            let playlist = Playlist(
                id: album.id,
                title: album.title,
                description: nil,
                thumbnailURL: album.thumbnailURL,
                trackCount: album.trackCount,
                author: album.artistsDisplay
            )
            onNavigateToPlaylist(playlist)
        } label: {
            Label("View Album", systemImage: "square.stack")
        }

        Divider()

        FavoritesContextMenu.menuItem(for: album, manager: favoritesManager)

        ShareContextMenu.menuItem(for: album)
    }

    // MARK: - Playlist Menu

    @ViewBuilder
    private static func playlistMenu(
        playlist: Playlist,
        favoritesManager: FavoritesManager,
        onNavigateToPlaylist: @escaping (Playlist) -> Void
    ) -> some View {
        Button {
            onNavigateToPlaylist(playlist)
        } label: {
            Label("View Playlist", systemImage: "music.note.list")
        }

        Divider()

        FavoritesContextMenu.menuItem(for: playlist, manager: favoritesManager)

        Divider()

        ShareContextMenu.menuItem(for: playlist)
    }

    // MARK: - Artist Menu

    @ViewBuilder
    private static func artistMenu(
        artist: Artist,
        favoritesManager: FavoritesManager,
        onNavigateToArtist: @escaping (Artist) -> Void
    ) -> some View {
        Button {
            onNavigateToArtist(artist)
        } label: {
            Label("View Artist", systemImage: "person")
        }

        Divider()

        FavoritesContextMenu.menuItem(for: artist, manager: favoritesManager)

        ShareContextMenu.menuItem(for: artist)
    }
}

// MARK: - Preview

#Preview {
    let song = Song(
        id: "test",
        title: "Test Song with a Very Long Title That Should Wrap",
        artists: [Artist(id: "artist1", name: "Test Artist")],
        videoId: "testVideo"
    )
    HStack {
        HomeSectionItemCard(item: .song(song)) {
            // No-op for preview
        }
        HomeSectionItemCard(item: .song(song), rank: 1) {
            // No-op for preview
        }
    }
    .padding()
}
