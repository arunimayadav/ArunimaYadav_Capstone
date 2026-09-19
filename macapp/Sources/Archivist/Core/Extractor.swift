import Foundation
import PDFKit

enum Extractor {
    /// Per-filetype text pull. OCR/vision fallback for scanned PDFs is a flagged
    /// stretch goal (plan.md section 12), not implemented here.
    static func extractText(from url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return extractPDF(url)
        case "docx":
            return extractOfficeXML(url, xmlPathPrefix: "word/document")
        case "pptx":
            return extractOfficeXML(url, xmlPathPrefix: "ppt/slides/slide")
        case "txt", "md":
            return try? String(contentsOf: url, encoding: .utf8)
        default:
            return nil
        }
    }

    private static func extractPDF(_ url: URL) -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        var text = ""
        for pageIndex in 0..<doc.pageCount {
            if let page = doc.page(at: pageIndex), let pageText = page.string {
                text += pageText + "\n"
            }
        }
        return text.isEmpty ? nil : text
    }

    /// .docx and .pptx are zip archives of XML. Unzip via /usr/bin/unzip (present on
    /// every Mac) and strip tags with a simple regex — avoids pulling in a third-party
    /// zip/XML library for the MVP (plan.md section 9).
    private static func extractOfficeXML(_ url: URL, xmlPathPrefix: String) -> String? {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", url.path, "-d", tempDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil) else {
            return nil
        }
        var xmlFiles: [URL] = []
        for entry in enumerator {
            guard let fileURL = entry as? URL else { continue }
            let relative = fileURL.path.replacingOccurrences(of: tempDir.path + "/", with: "")
            if relative.hasPrefix(xmlPathPrefix) && fileURL.pathExtension == "xml" {
                xmlFiles.append(fileURL)
            }
        }
        xmlFiles.sort { $0.path < $1.path }

        var combined = ""
        for file in xmlFiles {
            guard let xml = try? String(contentsOf: file, encoding: .utf8) else { continue }
            combined += stripXMLTags(xml) + "\n"
        }
        return combined.isEmpty ? nil : combined
    }

    private static func stripXMLTags(_ xml: String) -> String {
        var result = ""
        var insideTag = false
        for char in xml {
            if char == "<" { insideTag = true }
            else if char == ">" { insideTag = false }
            else if !insideTag { result.append(char) }
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
