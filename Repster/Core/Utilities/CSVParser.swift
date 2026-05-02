import Foundation

// MARK: - CSVParser

struct CSVParser {

    // MARK: - Result Types

    struct ParseResult {
        let headers: [String]
        let rows: [[String]]
        let totalRows: Int
    }

    struct PreviewResult {
        let headers: [String]
        let sampleRows: [[String]]
        let estimatedTotalRows: Int
    }

    struct ValidationError: Error, Identifiable, Sendable {
        let id: UUID
        let rowNumber: Int
        let reason: String
        let rawLine: String?

        init(rowNumber: Int, reason: String, rawLine: String? = nil) {
            self.id = UUID()
            self.rowNumber = rowNumber
            self.reason = reason
            self.rawLine = rawLine
        }
    }

    // MARK: - Public API

    static func parse(data: Data, encoding: String.Encoding = .utf8) throws -> ParseResult {
        if let text = String(data: data, encoding: encoding) {
            return try parseText(text)
        }
        guard let fallback = String(data: data, encoding: .isoLatin1) else {
            throw CSVParserError.invalidEncoding
        }
        return try parseText(fallback)
    }

    static func parsePreview(data: Data, maxRows: Int = 5, encoding: String.Encoding = .utf8) throws -> PreviewResult {
        let text: String
        if let utf8 = String(data: data, encoding: encoding) {
            text = utf8
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            text = latin1
        } else {
            throw CSVParserError.invalidEncoding
        }

        let allRows = parseFields(from: text)
        guard let headers = allRows.first, !headers.isEmpty else {
            throw CSVParserError.emptyFile
        }

        let dataRows = Array(allRows.dropFirst())
        let sampleRows = Array(dataRows.prefix(maxRows))

        // Estimate total lines (fast approximation — doesn't account for quoted newlines)
        let estimatedLines = text.reduce(into: 0) { count, char in
            if char == "\n" { count += 1 }
        }
        let estimatedDataRows = max(estimatedLines - 1, sampleRows.count) // -1 for header

        return PreviewResult(
            headers: headers,
            sampleRows: sampleRows,
            estimatedTotalRows: estimatedDataRows
        )
    }

    // MARK: - Core Parser (RFC 4180 State Machine)

    private static func parseText(_ text: String) throws -> ParseResult {
        let allRows = parseFields(from: text)
        guard let headers = allRows.first, !headers.isEmpty else {
            throw CSVParserError.emptyFile
        }
        let dataRows = Array(allRows.dropFirst())
        return ParseResult(headers: headers, rows: dataRows, totalRows: dataRows.count)
    }

    private static func parseFields(from text: String) -> [[String]] {
        // Normalize line endings: \r\n → \n
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        var iterator = normalized.makeIterator()
        var peeked: Character?

        func nextChar() -> Character? {
            if let p = peeked {
                peeked = nil
                return p
            }
            return iterator.next()
        }

        while let char = nextChar() {
            if inQuotes {
                if char == "\"" {
                    // Peek at next character to distinguish escaped quote from closing quote
                    let next = iterator.next()
                    if next == "\"" {
                        // Escaped quote: "" → literal "
                        currentField.append("\"")
                    } else {
                        // Closing quote
                        inQuotes = false
                        peeked = next
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                switch char {
                case "\"":
                    inQuotes = true
                case ",":
                    currentRow.append(currentField)
                    currentField = ""
                case "\n":
                    currentRow.append(currentField)
                    currentField = ""
                    rows.append(currentRow)
                    currentRow = []
                default:
                    currentField.append(char)
                }
            }
        }

        // Flush remaining content
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            // Guard against spurious empty final row (single empty string from trailing newline)
            let isSpuriousEmpty = currentRow.count == 1 && currentRow[0].isEmpty
            if !isSpuriousEmpty {
                rows.append(currentRow)
            }
        }

        return rows
    }
}

// MARK: - CSVParserError

enum CSVParserError: Error, LocalizedError {
    case invalidEncoding
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "Unable to read file encoding. Please ensure the file is UTF-8 encoded."
        case .emptyFile:
            return "The CSV file is empty or has no header row."
        }
    }
}
