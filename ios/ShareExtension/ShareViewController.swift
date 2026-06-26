import Social
import UniformTypeIdentifiers

final class ShareViewController: SLComposeServiceViewController {
    private let groupIdentifier = "group.com.chartgreen.hexcolorpreview"
    private let sharedImportKey = "sharedImportedPalettes"

    override func isContentValid() -> Bool {
        true
    }

    override func didSelectPost() {
        Task {
            let sharedText = await collectSharedText()
            let colors = ColorParser.parse(sharedText)

            if !colors.isEmpty {
                savePalette(colors)
            }

            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    override func configurationItems() -> [Any]! {
        []
    }

    private func collectSharedText() async -> String {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return contentText
        }

        var fragments: [String] = [contentText]
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    if let text = await loadString(from: provider, type: UTType.text.identifier) {
                        fragments.append(text)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let text = await loadString(from: provider, type: UTType.url.identifier) {
                        fragments.append(text)
                    }
                }
            }
        }
        return fragments.joined(separator: "\n")
    }

    private func loadString(from provider: NSItemProvider, type: String) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let url = item as? URL {
                    continuation.resume(returning: url.absoluteString)
                } else if let data = item as? Data {
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func savePalette(_ colors: [ColorItem]) {
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else { return }
        var palettes = loadPalettes(defaults)
        palettes.insert(
            SharedPalette(
                id: makeId(),
                name: defaultPaletteName(colors),
                createdAt: now(),
                colors: colors
            ),
            at: 0
        )
        defaults.set(try? JSONEncoder().encode(palettes), forKey: sharedImportKey)
    }

    private func loadPalettes(_ defaults: UserDefaults) -> [SharedPalette] {
        guard let data = defaults.data(forKey: sharedImportKey) else { return [] }
        return (try? JSONDecoder().decode([SharedPalette].self, from: data)) ?? []
    }
}

private struct ColorItem: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var hex: String
}

private struct SharedPalette: Codable, Identifiable {
    var id: String
    var name: String
    var createdAt: Int64
    var colors: [ColorItem]
}

private enum ColorParser {
    static func parse(_ value: String) -> [ColorItem] {
        value
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .compactMap { rawLine in
                let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let match = line.range(of: #"#?[0-9a-fA-F]{6}\b|#?[0-9a-fA-F]{3}\b"#, options: .regularExpression),
                      let hex = normalize(String(line[match])) else {
                    return nil
                }
                let name = line[..<match.lowerBound]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-:： "))
                return ColorItem(name: name.isEmpty ? commonName(hex) : name, hex: hex)
            }
    }

    static func normalize(_ value: String) -> String? {
        let cleaned = value.replacingOccurrences(of: "#", with: "")
        if cleaned.range(of: #"^[0-9a-fA-F]{3}$"#, options: .regularExpression) != nil {
            return "#" + cleaned.map { "\($0)\($0)" }.joined().uppercased()
        }
        if cleaned.range(of: #"^[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil {
            return "#" + cleaned.uppercased()
        }
        return nil
    }
}

private func now() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
}

private func makeId() -> String {
    "\(now())-\(UUID().uuidString.prefix(8))"
}

private func defaultPaletteName(_ colors: [ColorItem]) -> String {
    colors.prefix(2).map(\.name).joined(separator: "、") + "色系"
}

private func commonName(_ hex: String) -> String {
    [
        "#000000": "黑色", "#333333": "炭黑", "#808080": "灰色",
        "#F6E8C8": "奶油色", "#C9A77B": "奶茶色", "#B94A48": "磚紅",
        "#5F7C69": "鼠尾草綠", "#3B322B": "暖墨色", "#FFFFFF": "白色",
        "#FF0000": "紅色", "#FFD700": "金黃", "#2563EB": "藍色"
    ][hex] ?? "自訂色"
}
