import Photos
import UIKit

/// Saves daycare photos to the camera roll. Add-only Photos access (the app
/// never reads the library), always user-initiated — the Save button on the
/// photo viewer and the "Save all" on the daycare card. Brightwheel's CDN
/// links are signed and expire, so bytes come from the local cache first and
/// a download second; an expired link is a per-photo failure, never a crash.
@MainActor
enum PhotoSaver {
    enum SaveError: LocalizedError {
        case accessDenied
        case noImage

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Allow photo access for Two of Us in Settings to save photos."
            case .noImage:
                return "This photo isn't available anymore — Brightwheel's links expire."
            }
        }
    }

    /// The photo's bytes: the cached copy when it exists, else a fresh
    /// download from the signed CDN link. Nil when neither yields a
    /// decodable image.
    static func imageData(for event: MediaEvent) async -> Data? {
        if let data = event.mediaData, UIImage(data: data) != nil { return data }
        guard let url = event.remoteURL.flatMap(URL.init(string:)),
              let (data, response) = try? await URLSession.shared.data(from: url) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        return UIImage(data: data) != nil ? data : nil
    }

    /// One photo, for the viewer's Save button.
    static func save(_ event: MediaEvent) async throws {
        guard await requestAccess() else { throw SaveError.accessDenied }
        guard let data = await imageData(for: event) else { throw SaveError.noImage }
        try await write(data)
    }

    /// Every photo in `events`, for the card's "Save all". Access failure
    /// throws (nothing could save); a photo whose bytes are gone counts as
    /// a failure and the rest keep going.
    static func saveAll(_ events: [MediaEvent]) async throws -> (saved: Int, failed: Int) {
        guard await requestAccess() else { throw SaveError.accessDenied }
        var saved = 0
        var failed = 0
        for event in events {
            guard let data = await imageData(for: event) else { failed += 1; continue }
            do {
                try await write(data)
                saved += 1
            } catch {
                failed += 1
            }
        }
        return (saved, failed)
    }

    private static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }

    private static func write(_ data: Data) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }
}
