import Foundation

// MARK: - Decoding

enum TextLoader {
    /// Files on a real disk are not all UTF-8: LTspice writes UTF-16 logs,
    /// Windows tools write Latin-1. Guessing wrong turns a log into "L T s p".
    static func decode(_ data: Data) -> (text: String, encoding: String) {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            let body = data.dropFirst(3)
            return (String(decoding: body, as: UTF8.self), "UTF-8")
        }
        if data.starts(with: [0xFF, 0xFE]) {
            return (decodeUTF16(data.dropFirst(2), littleEndian: true), "UTF-16 LE")
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return (decodeUTF16(data.dropFirst(2), littleEndian: false), "UTF-16 BE")
        }

        // No BOM: interleaved zero bytes give UTF-16 away.
        let sample = data.prefix(2048)
        if sample.count >= 4 {
            var evenZeros = 0
            var oddZeros = 0
            for (offset, byte) in sample.enumerated() where byte == 0 {
                if offset % 2 == 0 { evenZeros += 1 } else { oddZeros += 1 }
            }
            let threshold = sample.count / 8
            // No BOM in the file, so none may be written back on save.
            if oddZeros > threshold, evenZeros <= oddZeros / 4 {
                return (decodeUTF16(data, littleEndian: true), "UTF-16 LE (no BOM)")
            }
            if evenZeros > threshold, oddZeros <= evenZeros / 4 {
                return (decodeUTF16(data, littleEndian: false), "UTF-16 BE (no BOM)")
            }
        }

        if let utf8 = String(data: data, encoding: .utf8) { return (utf8, "UTF-8") }
        if let latin = String(data: data, encoding: .windowsCP1252) { return (latin, "Windows-1252") }
        return (String(decoding: data, as: UTF8.self), "UTF-8 (lossy)")
    }

    /// Writes back in the encoding the file arrived in — rewriting an LTspice
    /// UTF-16 log as UTF-8 would break the tool that produced it.
    static func encode(_ text: String, as encoding: String) -> Data {
        switch encoding {
        case "UTF-16 LE": return utf16Data(text, littleEndian: true, bom: true)
        case "UTF-16 BE": return utf16Data(text, littleEndian: false, bom: true)
        case "UTF-16 LE (no BOM)": return utf16Data(text, littleEndian: true, bom: false)
        case "UTF-16 BE (no BOM)": return utf16Data(text, littleEndian: false, bom: false)
        case "Windows-1252": return text.data(using: .windowsCP1252) ?? Data(text.utf8)
        default: return Data(text.utf8)
        }
    }

    private static func utf16Data(_ text: String, littleEndian: Bool, bom: Bool) -> Data {
        var bytes: [UInt8] = bom ? (littleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF]) : []
        bytes.reserveCapacity(text.utf16.count * 2 + 2)
        for unit in text.utf16 {
            let low = UInt8(unit & 0xFF)
            let high = UInt8(unit >> 8)
            bytes.append(contentsOf: littleEndian ? [low, high] : [high, low])
        }
        return Data(bytes)
    }

    private static func decodeUTF16<D: DataProtocol>(_ data: D, littleEndian: Bool) -> String {
        let bytes = Array(data)
        var units: [UInt16] = []
        units.reserveCapacity(bytes.count / 2)
        var index = 0
        while index + 1 < bytes.count {
            let low = UInt16(bytes[index])
            let high = UInt16(bytes[index + 1])
            units.append(littleEndian ? (high << 8 | low) : (low << 8 | high))
            index += 2
        }
        return String(decoding: units, as: UTF16.self)
    }
}

// MARK: - Kind detection

enum TextKind: String, CaseIterable, Identifiable {
    case json = "JSON"
    case table = "Table"
    case log = "Log"
    case config = "Config"
    case plain = "Plain Text"

    var id: String { rawValue }
}

struct Delimiter {
    let character: Character
    let name: String
}

enum TextDetector {
    private static let levelPattern = try! NSRegularExpression(
        pattern: #"\b(TRACE|DEBUG|INFO|NOTICE|WARN(?:ING)?|ERROR|FATAL|CRITICAL)\b"#)
    private static let timestampPattern = try! NSRegularExpression(
        pattern: #"(^\s*\[?\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2})|(^\s*\d{2}:\d{2}:\d{2})|(^\s*\w{3}\s+\w{3}\s+\d+\s+\d{2}:\d{2}:\d{2})"#)
    private static let settingPattern = try! NSRegularExpression(
        pattern: #"^\s*[\w.\-\[\]/]+\s*[:=]\s*\S"#)

    /// Cheap structural sniffing over the first slice of the file.
    static func detect(text: String) -> (kind: TextKind, delimiter: Delimiter?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if JSONParser.parse(text).root != nil { return (.json, nil) }
        }

        let lines = sampleLines(of: text)
        guard !lines.isEmpty else { return (.plain, nil) }

        if let delimiter = detectDelimiter(in: lines) { return (.table, delimiter) }

        let logScore = ratio(of: lines) { line in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            return timestampPattern.firstMatch(in: line, range: range) != nil
                || levelPattern.firstMatch(in: line, range: range) != nil
        }
        if logScore >= 0.3 { return (.log, nil) }

        let configScore = ratio(of: lines) { line in
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("#") || trimmedLine.hasPrefix(";") || trimmedLine.hasPrefix("//") { return true }
            if trimmedLine.hasPrefix("[") && trimmedLine.hasSuffix("]") { return true }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            return settingPattern.firstMatch(in: line, range: range) != nil
        }
        if configScore >= 0.5 { return (.config, nil) }

        return (.plain, nil)
    }

    private static func sampleLines(of text: String, limit: Int = 60) -> [String] {
        var lines: [String] = []
        text.enumerateLines { line, stop in
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(line)
                if lines.count >= limit { stop = true }
            }
        }
        return lines
    }

    private static func ratio(of lines: [String], matching test: (String) -> Bool) -> Double {
        guard !lines.isEmpty else { return 0 }
        return Double(lines.filter(test).count) / Double(lines.count)
    }

    private static func detectDelimiter(in lines: [String]) -> Delimiter? {
        guard lines.count >= 3 else { return nil }
        let candidates: [Delimiter] = [
            Delimiter(character: "\t", name: "Tab"),
            Delimiter(character: ",", name: "Comma"),
            Delimiter(character: ";", name: "Semicolon"),
            Delimiter(character: "|", name: "Pipe")
        ]
        for candidate in candidates {
            let counts = lines.map { line in line.filter { $0 == candidate.character }.count }
            guard let first = counts.first, first >= 1 else { continue }
            let agreeing = counts.filter { $0 == first }.count
            if Double(agreeing) / Double(counts.count) >= 0.9 { return candidate }
        }
        return nil
    }
}

// MARK: - Table model

struct TextTable {
    let headers: [String]
    let rows: [[String]]
    let hasHeaderRow: Bool
    let columnWidths: [Int]

    static func parse(text: String, delimiter: Delimiter) -> TextTable {
        var rows: [[String]] = []
        text.enumerateLines { line, _ in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return }
            rows.append(split(line: line, by: delimiter.character))
        }
        guard !rows.isEmpty else {
            return TextTable(headers: [], rows: [], hasHeaderRow: false, columnWidths: [])
        }

        // A header row is all text; a data row usually carries numbers.
        let first = rows[0]
        let rest = rows.dropFirst().prefix(20)
        let firstIsText = first.allSatisfy { Double($0.trimmingCharacters(in: .whitespaces)) == nil }
        let restHasNumbers = rest.contains { row in
            row.contains { Double($0.trimmingCharacters(in: .whitespaces)) != nil }
        }
        let hasHeaderRow = firstIsText && restHasNumbers && rows.count > 1

        let headers: [String]
        let body: [[String]]
        if hasHeaderRow {
            headers = first
            body = Array(rows.dropFirst())
        } else {
            headers = (1...(rows.map(\.count).max() ?? 1)).map { "\($0)" }
            body = rows
        }

        let columnCount = max(headers.count, body.map(\.count).max() ?? 0)
        var widths = Array(repeating: 0, count: columnCount)
        for (index, header) in headers.enumerated() where index < columnCount {
            widths[index] = header.count
        }
        for row in body.prefix(200) {
            for (index, cell) in row.enumerated() where index < columnCount {
                widths[index] = min(max(widths[index], cell.count), 48)
            }
        }
        return TextTable(headers: headers, rows: body, hasHeaderRow: hasHeaderRow, columnWidths: widths)
    }

    /// Handles quoted fields so an address containing a comma stays one cell.
    private static func split(line: String, by delimiter: Character) -> [String] {
        guard line.contains("\"") else { return line.components(separatedBy: String(delimiter)) }
        var cells: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        var pending: Character?
        while let character = pending ?? iterator.next() {
            pending = nil
            if character == "\"" {
                if inQuotes, let next = iterator.next() {
                    if next == "\"" { current.append("\"") } else { inQuotes = false; pending = next }
                } else {
                    inQuotes.toggle()
                }
            } else if character == delimiter && !inQuotes {
                cells.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current)
        return cells
    }
}
