import Foundation

struct BuildMetadata {
    static let fields = ["compiler", "sdk", "macOS", "sourceRevision", "xcode"]
    let status: String
    let values: [String: String]
    var json: [String: String] { values.merging(["status": status]) { _, new in new } }

    static func read(_ raw: String?) -> BuildMetadata {
        let unavailable = Dictionary(uniqueKeysWithValues: fields.map { ($0, "unavailable") })
        guard let raw else { return BuildMetadata(status: "unavailable", values: unavailable) }
        guard raw.utf8.count <= 32_768, let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data), let metadata = object as? [String: Any] else {
            return BuildMetadata(status: "invalid", values: unavailable)
        }
        var values = unavailable
        for field in fields {
            guard let value = metadata[field] else { continue }
            guard let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.utf8.count <= 4_096, !text.unicodeScalars.contains(where: { $0.value < 32 && $0.value != 10 && $0.value != 9 }) else {
                return BuildMetadata(status: "invalid", values: unavailable)
            }
            values[field] = text
        }
        return BuildMetadata(status: fields.contains(where: { metadata[$0] != nil }) ? "provided" : "unavailable", values: values)
    }
}
