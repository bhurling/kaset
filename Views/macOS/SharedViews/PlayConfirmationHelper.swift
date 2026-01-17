import SwiftUI

// MARK: - PlayConfirmationHelper

/// Helper for showing a confirmation dialog when playing a song.
/// Provides "Play now" and "Play next" options.
@available(macOS 26.0, *)
@MainActor
enum PlayConfirmationHelper {
    /// Shows a confirmation dialog for playing a song.
    /// - Parameters:
    ///   - song: The song to play
    ///   - playerService: The player service to use
    ///   - isPresented: Binding to control dialog visibility
    /// - Returns: A view builder for the confirmation dialog
    @ViewBuilder
    static func confirmationDialog(
        for song: Song,
        playerService: PlayerService,
        isPresented: Binding<Bool>
    ) -> some View {
        EmptyView()
            .confirmationDialog(
                "This will interrupt the current song",
                isPresented: isPresented,
                titleVisibility: .visible
            ) {
                Button("Play Now") {
                    Task {
                        await playerService.play(song: song)
                    }
                }
                
                Button("Play Next") {
                    playerService.insertNextInQueue([song])
                }
                
                Button("Cancel", role: .cancel) {
                    // Dialog dismisses automatically
                }
            }
    }
    
    /// Shows a confirmation dialog for playing a queue of songs.
    /// - Parameters:
    ///   - songs: The songs to play
    ///   - startingAt: The index to start playing from
    ///   - playerService: The player service to use
    ///   - isPresented: Binding to control dialog visibility
    /// - Returns: A view builder for the confirmation dialog
    @ViewBuilder
    static func confirmationDialog(
        forQueue songs: [Song],
        startingAt index: Int,
        playerService: PlayerService,
        isPresented: Binding<Bool>
    ) -> some View {
        EmptyView()
            .confirmationDialog(
                "This will interrupt the current song",
                isPresented: isPresented,
                titleVisibility: .visible
            ) {
                Button("Play Now") {
                    Task {
                        await playerService.playQueue(songs, startingAt: index)
                    }
                }
                
                Button("Play Next") {
                    // Insert the selected song and all songs after it
                    let songsToInsert = Array(songs[index...])
                    playerService.insertNextInQueue(songsToInsert)
                }
                
                Button("Cancel", role: .cancel) {
                    // Dialog dismisses automatically
                }
            }
    }
}

// MARK: - PlayConfirmationModifier

/// View modifier that adds play confirmation dialog support to a view.
@available(macOS 26.0, *)
struct PlayConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let song: Song?
    let songs: [Song]?
    let startIndex: Int
    let playerService: PlayerService
    
    func body(content: Content) -> some View {
        content
            .background {
                if let song {
                    PlayConfirmationHelper.confirmationDialog(
                        for: song,
                        playerService: self.playerService,
                        isPresented: self.$isPresented
                    )
                } else if let songs {
                    PlayConfirmationHelper.confirmationDialog(
                        forQueue: songs,
                        startingAt: self.startIndex,
                        playerService: self.playerService,
                        isPresented: self.$isPresented
                    )
                }
            }
    }
}

@available(macOS 26.0, *)
extension View {
    /// Adds a play confirmation dialog to the view.
    /// - Parameters:
    ///   - isPresented: Binding to control dialog visibility
    ///   - song: The song to play (for single song playback)
    ///   - playerService: The player service to use
    /// - Returns: A view with the play confirmation dialog
    func playConfirmation(
        isPresented: Binding<Bool>,
        song: Song,
        playerService: PlayerService
    ) -> some View {
        modifier(PlayConfirmationModifier(
            isPresented: isPresented,
            song: song,
            songs: nil,
            startIndex: 0,
            playerService: playerService
        ))
    }
    
    /// Adds a play confirmation dialog to the view for queue playback.
    /// - Parameters:
    ///   - isPresented: Binding to control dialog visibility
    ///   - songs: The songs to play as a queue
    ///   - startingAt: The index to start playing from
    ///   - playerService: The player service to use
    /// - Returns: A view with the play confirmation dialog
    func playConfirmation(
        isPresented: Binding<Bool>,
        songs: [Song],
        startingAt index: Int,
        playerService: PlayerService
    ) -> some View {
        modifier(PlayConfirmationModifier(
            isPresented: isPresented,
            song: nil,
            songs: songs,
            startIndex: index,
            playerService: playerService
        ))
    }
}

