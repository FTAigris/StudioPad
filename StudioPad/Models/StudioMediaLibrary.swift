import Foundation
import PhotosUI
import UniformTypeIdentifiers

enum StudioMediaLibrary {
    static func importItems(_ items: [PhotosPickerItem]) async throws -> [String] {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        var filenames: [String] = []
        for item in items {
            guard let data = try await item.loadTransferable(type: Data.self) else { continue }
            let type = item.supportedContentTypes.first
            let fileExtension = type?.preferredFilenameExtension ?? "dat"
            let filename = "\(UUID().uuidString).\(fileExtension)"
            try data.write(to: directoryURL.appendingPathComponent(filename), options: .atomic)
            filenames.append(filename)
        }
        return filenames
    }

    static func url(for filename: String) -> URL? {
        guard !filename.isEmpty else { return nil }
        let url = directoryURL.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("StudioPadMedia", isDirectory: true)
    }
}
