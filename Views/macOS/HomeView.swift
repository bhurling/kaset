import SwiftUI

/// Home view displaying personalized content sections.
@available(macOS 26.0, *)
struct HomeView: View {
    @State var viewModel: HomeViewModel
    @Environment(PlayerService.self) private var playerService
    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(SongLikeStatusManager.self) private var likeStatusManager
    @State private var navigationPath = NavigationPath()
    @State private var networkMonitor = NetworkMonitor.shared

    var body: some View {
        NavigationStack(path: self.$navigationPath) {
            Group {
                if !self.networkMonitor.isConnected {
                    ErrorView(
                        title: "No Connection",
                        message: "Please check your internet connection and try again."
                    ) {
                        Task { await self.viewModel.refresh() }
                    }
                } else {
                    switch self.viewModel.loadingState {
                    case .idle, .loading:
                        HomeLoadingView()
                    case .loaded, .loadingMore:
                        self.contentView
                    case let .error(error):
                        ErrorView(error: error) {
                            Task { await self.viewModel.refresh() }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Home")
            .navigationDestinations(client: self.viewModel.client)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlayerBar()
        }
        .onAppear {
            if self.viewModel.loadingState == .idle {
                Task {
                    await self.viewModel.load()
                }
            }
        }
        .refreshable {
            await self.viewModel.refresh()
        }

    }

    // MARK: - Views

    private var contentView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                // Favorites section (hidden when empty)
                if self.favoritesManager.isVisible {
                    FavoritesSection(onNavigate: { destination in
                        if let playlist = destination as? Playlist {
                            self.navigationPath.append(playlist)
                        } else if let artist = destination as? Artist {
                            self.navigationPath.append(artist)
                        } else if let podcastShow = destination as? PodcastShow {
                            self.navigationPath.append(podcastShow)
                        }
                    })
                    .staggeredAppearance(index: 0)
                }

                // API sections - use stable id without array enumeration
                ForEach(self.viewModel.sections) { section in
                    self.sectionView(section)
                        .task {
                            await self.prefetchImagesAsync(for: section)
                        }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    private func sectionView(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.title2)
                .fontWeight(.semibold)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    // Use stable ID from items, avoid enumeration for non-chart sections
                    if section.isChart {
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                            HomeSectionItemCard(item: item, rank: index + 1) {
                                self.playItem(item, in: section, at: index)
                            }
                            .contextMenu {
                                self.contextMenuItems(for: item, in: section, at: index)
                            }
                        }
                    } else {
                        ForEach(section.items) { item in
                            HomeSectionItemCard(item: item) {
                                self.playItem(item, in: section, at: 0)
                            }
                            .contextMenu {
                                self.contextMenuItems(for: item, in: section, at: 0)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for item: HomeSectionItem, in _: HomeSection, at _: Int) -> some View {
        HomeSectionItemContextMenu.menu(
            for: item,
            playerService: self.playerService,
            favoritesManager: self.favoritesManager,
            likeStatusManager: self.likeStatusManager,
            onNavigateToPlaylist: { playlist in
                self.navigationPath.append(playlist)
            },
            onNavigateToArtist: { artist in
                self.navigationPath.append(artist)
            }
        )
    }

    // MARK: - Image Prefetching

    private static let thumbnailDisplaySize = CGSize(width: 160, height: 160)

    private func prefetchImagesAsync(for section: HomeSection) async {
        // Early exit if task is cancelled
        guard !Task.isCancelled else { return }

        let urls = section.items.prefix(10).compactMap { $0.thumbnailURL?.highQualityThumbnailURL }
        guard !urls.isEmpty else { return }

        await ImageCache.shared.prefetch(
            urls: urls,
            targetSize: Self.thumbnailDisplaySize,
            maxConcurrent: 4
        )
    }

    // MARK: - Actions

    private func playItem(_ item: HomeSectionItem, in _: HomeSection, at _: Int) {
        switch item {
        case .song:
            // Single click does nothing for songs - use context menu (right-click) for actions
            break
        case let .playlist(playlist):
            // Navigate to playlist detail
            self.navigationPath.append(playlist)
        case let .album(album):
            // For now, we'll create a playlist-like navigation for albums
            // In a full implementation, we'd have an AlbumDetailView
            let playlist = Playlist(
                id: album.id,
                title: album.title,
                description: nil,
                thumbnailURL: album.thumbnailURL,
                trackCount: album.trackCount,
                author: album.artistsDisplay
            )
            self.navigationPath.append(playlist)
        case let .artist(artist):
            // Navigate to artist detail
            self.navigationPath.append(artist)
        }
    }
}

#Preview {
    let authService = AuthService()
    let client = YTMusicClient(authService: authService, webKitManager: .shared)
    HomeView(viewModel: HomeViewModel(client: client))
        .environment(PlayerService())
        .environment(FavoritesManager.shared)
}
