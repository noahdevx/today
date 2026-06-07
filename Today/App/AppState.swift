import Foundation
import SwiftData

/// App-wide state and the single shared SwiftData container.
///
/// Why a singleton: both the SwiftUI `MenuBarExtra` scene and the AppKit-hosted
/// floating panel must read/write the exact same store. Creating one container
/// here and sharing it avoids two separate databases.
@MainActor
@Observable
final class AppState {
    /// Process-wide shared instance.
    static let shared = AppState()

    /// The one SwiftData container every view's `modelContext` is derived from.
    let modelContainer: ModelContainer

    /// Builds the shared container once. Private so the singleton can't be
    /// duplicated.
    private init() {
        do {
            // `isStoredInMemoryOnly: false` = persist to disk (the app's on-disk
            // SQLite store) so data survives relaunches.
            let configuration = ModelConfiguration(isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: TodayTask.self, configurations: configuration)
        } catch {
            // If the store can't be opened the app is unusable, so fail loudly
            // rather than limping along without persistence.
            fatalError("Failed to create the SwiftData ModelContainer: \(error)")
        }
    }
}
