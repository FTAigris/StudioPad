import Foundation
import PhotosUI
import SwiftUI
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
            let filename = "\(UUID().uuidString)--Elemento.\(fileExtension)"
            try data.write(
                to: directoryURL.appendingPathComponent(filename),
                options: Data.WritingOptions.atomic
            )
            filenames.append(filename)
        }
        return filenames
    }

    static func importFiles(_ urls: [URL]) throws -> [String] {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        return try urls.map { url in
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }

            let originalName = sanitizedFilename(url.lastPathComponent)
            let filename = "\(UUID().uuidString)--\(originalName)"
            let destination = directoryURL.appendingPathComponent(filename)
            try FileManager.default.copyItem(at: url, to: destination)
            return filename
        }
    }

    static func url(for filename: String) -> URL? {
        guard !filename.isEmpty else { return nil }
        let url = directoryURL.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func displayName(for filename: String) -> String {
        filename.components(separatedBy: "--").last ?? filename
    }

    private static func sanitizedFilename(_ filename: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = filename.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "Archivo" : cleaned
    }

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("StudioPadMedia", isDirectory: true)
    }
}
