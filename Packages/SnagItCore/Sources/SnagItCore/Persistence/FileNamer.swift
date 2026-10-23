import Foundation

/// 匯出檔名：`SnagItForever yyyy-MM-dd HH.mm.ss.<副檔名>`，重名時在副檔名前加序號 ` 2`、` 3`…（FR-017）。
public enum FileNamer {
    public static func uniqueURL(
        in folder: URL, date: Date, ext: String, timeZone: TimeZone = .current
    ) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = "SnagItForever \(formatter.string(from: date))"

        var candidate = folder.appendingPathComponent("\(base).\(ext)")
        var sequence = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(sequence).\(ext)")
            sequence += 1
        }
        return candidate
    }
}
