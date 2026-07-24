import Foundation

#if canImport(PDFKit)
import PDFKit
#endif

public enum DocumentLoaderError: Error, CustomStringConvertible {
    case unsupportedFile(URL)
    case unreadableFile(URL)
    case pdfTextUnavailable(URL)

    public var description: String {
        switch self {
        case .unsupportedFile(let url):
            return "Unsupported file type: \(url.path)"
        case .unreadableFile(let url):
            return "Could not read file: \(url.path)"
        case .pdfTextUnavailable(let url):
            return "Could not extract text from PDF: \(url.path)"
        }
    }
}

public enum DocumentLoader {
    public static let supportedExtensions: Set<String> = ["md", "markdown", "txt", "text", "pdf"]

    public static func loadDocuments(from inputURLs: [URL]) throws -> [LocalDocument] {
        var files: [URL] = []

        for inputURL in inputURLs {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
                throw DocumentLoaderError.unreadableFile(inputURL)
            }

            if isDirectory.boolValue {
                let enumerator = FileManager.default.enumerator(
                    at: inputURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )

                while let fileURL = enumerator?.nextObject() as? URL {
                    let ext = fileURL.pathExtension.lowercased()
                    guard supportedExtensions.contains(ext) else { continue }
                    files.append(fileURL)
                }
            } else {
                files.append(inputURL)
            }
        }

        return try files
            .sorted { $0.path < $1.path }
            .map(loadDocument)
            .filter { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public static func loadDocument(from fileURL: URL) throws -> LocalDocument {
        let ext = fileURL.pathExtension.lowercased()
        let title = fileURL.deletingPathExtension().lastPathComponent

        switch ext {
        case "md", "markdown", "txt", "text":
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
                throw DocumentLoaderError.unreadableFile(fileURL)
            }
            return LocalDocument(sourcePath: fileURL.path, title: title, body: text)

        case "pdf":
            let text = try extractPDFText(from: fileURL)
            return LocalDocument(sourcePath: fileURL.path, title: title, body: text)

        default:
            throw DocumentLoaderError.unsupportedFile(fileURL)
        }
    }

    private static func extractPDFText(from fileURL: URL) throws -> String {
        #if canImport(PDFKit)
        guard let pdf = PDFDocument(url: fileURL) else {
            throw DocumentLoaderError.unreadableFile(fileURL)
        }

        var pages: [String] = []
        for index in 0..<pdf.pageCount {
            if let pageText = pdf.page(at: index)?.string {
                pages.append(pageText)
            }
        }

        let text = pages.joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentLoaderError.pdfTextUnavailable(fileURL)
        }
        return text
        #else
        throw DocumentLoaderError.unsupportedFile(fileURL)
        #endif
    }
}
