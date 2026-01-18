import SwiftUI

// MARK: - QueueView

/// Right sidebar panel displaying the playback queue.
@available(macOS 26.0, *)
struct QueueView: View {
    @Environment(PlayerService.self) private var playerService
    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(\.showCommandBar) private var showCommandBar

    /// Namespace for glass effect morphing.
    @Namespace private var queueNamespace

    /// Index of the row being dragged (nil when not dragging).
    @State private var draggingIndex: Int?

    /// Current Y offset of the drag gesture.
    @State private var dragOffset: CGFloat = 0

    /// Y position within the row where the drag started.
    @State private var dragStartY: CGFloat = 0

    /// Height of each row for calculating drop position.
    private let rowHeight: CGFloat = 56

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: 0) {
                // Header
                self.headerView

                Divider()
                    .opacity(0.3)

                // Content
                self.contentView
            }
            .frame(width: 560)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            .glassEffectID("queuePanel", in: self.queueNamespace)
        }
        .glassEffectTransition(.materialize)
        .accessibilityIdentifier(AccessibilityID.Queue.container)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Up Next")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if self.playerService.queue.isEmpty {
            self.emptyQueueView
        } else {
            self.queueListView
        }
    }

    private var emptyQueueView: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("No Queue")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Play songs from a playlist or album to build your queue.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(AccessibilityID.Queue.emptyState)
    }

    private var queueListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(self.playerService.queue.enumerated()), id: \.offset) { index, song in
                    self.queueRow(for: song, at: index)
                        .accessibilityIdentifier(AccessibilityID.Queue.row(index: index))
                }
            }
            .padding(.vertical, 8)
        }
        .accessibilityIdentifier(AccessibilityID.Queue.scrollView)
    }

    // MARK: - Queue Row

    @ViewBuilder
    private func queueRow(for song: Song, at index: Int) -> some View {
        let isCurrentTrack = index == self.playerService.currentIndex
        let isDragging = self.draggingIndex == index
        let dropInfo = self.dropTargetInfo(for: index)

        ZStack(alignment: .top) {
            // Drop indicator above
            if dropInfo.showAbove {
                self.dropIndicator
                    .offset(y: -4)
            }

            QueueRowView(
                song: song,
                isCurrentTrack: isCurrentTrack,
                index: index,
                favoritesManager: self.favoritesManager,
                playerService: self.playerService,
                onRemove: { self.playerService.removeFromQueue(at: index) }
            )
            .opacity(isDragging ? 0.4 : 1.0)
            .offset(y: isDragging ? self.dragOffset : 0)
            .zIndex(isDragging ? 100 : 0)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if self.draggingIndex == nil {
                            self.draggingIndex = index
                            self.dragStartY = value.startLocation.y
                        }
                        self.dragOffset = value.translation.height
                    }
                    .onEnded { _ in
                        self.handleDragEnd(from: index)
                    }
            )

            // Drop indicator below (only for last item)
            if dropInfo.showBelow {
                self.dropIndicator
                    .offset(y: self.rowHeight - 4)
            }
        }
    }

    /// Calculate if this row should show a drop indicator based on current mouse position.
    private func dropTargetInfo(for index: Int) -> (showAbove: Bool, showBelow: Bool) {
        guard let sourceIndex = self.draggingIndex else {
            return (false, false)
        }

        // Calculate the virtual Y position of the mouse in the list
        let globalY = CGFloat(sourceIndex) * self.rowHeight + self.dragStartY + self.dragOffset

        // Determine which row the mouse is over
        let targetRow = max(0, min(Int(globalY / self.rowHeight), self.playerService.queue.count - 1))

        // Don't show indicator on the dragged row itself
        if index == sourceIndex || targetRow == sourceIndex {
            return (false, false)
        }

        // Check if this is the target row
        guard index == targetRow else {
            return (false, false)
        }

        // Determine if mouse is in upper or lower half of the target row
        let positionInRow = globalY - CGFloat(targetRow) * self.rowHeight
        let isUpperHalf = positionInRow < self.rowHeight / 2

        return (isUpperHalf, !isUpperHalf)
    }

    private var dropIndicator: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)

            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 12)
        .frame(height: 8)
    }

    // MARK: - Drag Handling

    private func handleDragEnd(from sourceIndex: Int) {
        // Calculate the virtual Y position of the mouse in the list
        let globalY = CGFloat(sourceIndex) * self.rowHeight + self.dragStartY + self.dragOffset

        // Determine which row the mouse is over
        let targetRow = max(0, min(Int(globalY / self.rowHeight), self.playerService.queue.count - 1))

        // Determine if mouse is in upper or lower half of the target row
        let positionInRow = globalY - CGFloat(targetRow) * self.rowHeight
        let dropBelow = positionInRow >= self.rowHeight / 2

        // Calculate insert index based on drop position
        var insertIndex = dropBelow ? targetRow + 1 : targetRow

        // Adjust for removal of source item
        if sourceIndex < insertIndex {
            insertIndex -= 1
        }

        // Perform reorder if destination is different from source
        if insertIndex != sourceIndex, insertIndex >= 0, insertIndex < self.playerService.queue.count {
            var videoIds = self.playerService.queue.map(\.videoId)
            let movedId = videoIds.remove(at: sourceIndex)
            videoIds.insert(movedId, at: insertIndex)
            self.playerService.reorderQueue(videoIds: videoIds)
        }

        // Reset drag state
        withAnimation(.easeOut(duration: 0.2)) {
            self.draggingIndex = nil
            self.dragOffset = 0
            self.dragStartY = 0
        }
    }
}

// MARK: - QueueRowView

@available(macOS 26.0, *)
private struct QueueRowView: View {
    let song: Song
    let isCurrentTrack: Bool
    let index: Int
    let favoritesManager: FavoritesManager
    let playerService: PlayerService
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Now Playing indicator or track number
            self.leadingIndicator
                .frame(width: 24)

            // Thumbnail
            CachedAsyncImage(url: self.song.thumbnailURL?.highQualityThumbnailURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .overlay {
                        CassetteIcon(size: 16)
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(self.song.title)
                    .font(.system(size: 13, weight: self.isCurrentTrack ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(self.isCurrentTrack ? .red : .primary)

                Text(self.song.artistsDisplay.isEmpty ? "Unknown Artist" : self.song.artistsDisplay)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Duration
            if let duration = self.song.duration {
                Text(self.formatDuration(duration))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 56)
        .background(self.backgroundColor)
        .contentShape(Rectangle())
        .onHover { hovering in
            self.isHovering = hovering
        }
        .contextMenu {
            if !self.isCurrentTrack {
                Button {
                    self.moveToNext()
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }

            Button {
                self.moveToLast()
            } label: {
                Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward")
            }

                Button {
                    Task {
                        await self.playerService.playFromQueue(at: self.index)
                    }
                } label: {
                    Label("Play Now", systemImage: "play.fill")
                }

                Divider()
            }

            FavoritesContextMenu.menuItem(for: self.song, manager: self.favoritesManager)

            Divider()

            ShareContextMenu.menuItem(for: self.song)

            if !self.isCurrentTrack {
                Divider()

                Button(role: .destructive) {
                    self.onRemove()
                } label: {
                    Label("Remove from Queue", systemImage: "minus.circle")
                }
            }
        }
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        if self.isCurrentTrack {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(self.playerService.isPlaying ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
                .symbolEffect(
                    .variableColor.iterative,
                    options: .repeating,
                    isActive: self.playerService.isPlaying
                )
        } else {
            Text("\(self.index + 1)")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }

    private var backgroundColor: Color {
        if self.isCurrentTrack {
            return Color.red.opacity(0.1)
        } else if self.isHovering {
            return Color.primary.opacity(0.05)
        }
        return .clear
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func moveToNext() {
        // Remove the song from its current position
        let song = self.playerService.queue[self.index]
        self.playerService.removeFromQueue(at: self.index)

        // Insert it right after the current track
        self.playerService.insertNextInQueue([song])
    }

    private func moveToLast() {
        // Remove the song from its current position
        let song = self.playerService.queue[self.index]
        self.playerService.removeFromQueue(at: self.index)

        // Append it to the end of the queue
        self.playerService.appendToQueue([song])
    }
}

@available(macOS 26.0, *)
#Preview("Queue View") {
    let playerService = PlayerService()
    QueueView()
        .environment(playerService)
        .environment(FavoritesManager.shared)
        .frame(height: 600)
}

@available(macOS 26.0, *)
#Preview("Queue View with Items") {
    let playerService = PlayerService()
    // Note: In real use, queue would be populated via playQueue()
    QueueView()
        .environment(playerService)
        .environment(FavoritesManager.shared)
        .frame(height: 600)
}
