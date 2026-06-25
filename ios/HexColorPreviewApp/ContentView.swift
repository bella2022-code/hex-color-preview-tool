import SwiftUI

private let firebaseApiKey = "AIzaSyB6624vmNjfIbrQ6WZZesLxgDps3LwT_BM"
private let firebaseProjectId = "hex-color-preview-tool"
private let appGroupIdentifier = "group.com.bella.hexcolorpreview"
private let sharedImportKey = "sharedImportedPalettes"

struct ColorItem: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var hex: String

    init(id: String = UUID().uuidString, name: String, hex: String) {
        self.id = id
        self.name = name
        self.hex = hex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decode(String.self, forKey: .name)
        hex = try container.decode(String.self, forKey: .hex)
    }

    var swiftColor: Color {
        Color(hex: hex)
    }
}

struct SavedColor: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var hex: String
    var createdAt: Int64
}

struct ColorPalette: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var createdAt: Int64
    var colors: [ColorItem]
}

struct HistoryItem: Codable, Identifiable, Hashable {
    var id: String
    var signature: String
    var createdAt: Int64
    var colors: [ColorItem]
}

struct AuthSession: Codable {
    var email: String
    var localId: String
    var idToken: String
}

struct ContentView: View {
    @State private var input = """
    Postcard Cream #F6E8C8
    Milk Tea #C9A77B
    Post Red #B94A48
    Stamp Green #5F7C69
    Warm Ink #3B322B
    """
    @State private var savedColors: [SavedColor] = Store.load("savedColors")
    @State private var savedPalettes: [ColorPalette] = Store.load("savedPalettes")
    @State private var history: [HistoryItem] = Store.load("history")
    @State private var session: AuthSession? = Store.loadSession()
    @State private var email = ""
    @State private var password = ""
    @State private var message = "本機儲存"
    @State private var showAccount = false
    @State private var selectedTab = 0

    private var parsedColors: [ColorItem] {
        ColorParser.parse(input)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("輸入 Hex 色碼或色票清單") {
                    TextEditor(text: $input)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 132)
                        .onChange(of: input) { _, _ in recordHistory() }

                    HStack {
                        Label("\(parsedColors.count) 個顏色", systemImage: "number")
                        Spacer()
                        Button("儲存色系", action: savePalette)
                            .disabled(parsedColors.isEmpty)
                    }
                }

                Section("顏色預覽") {
                    ForEach(parsedColors) { item in
                        ColorRow(item: item) {
                            saveColor(item)
                        }
                    }
                }

                Section {
                    Picker("收藏", selection: $selectedTab) {
                        Text("歷史").tag(0)
                        Text("單色").tag(1)
                        Text("色系").tag(2)
                    }
                    .pickerStyle(.segmented)

                    if selectedTab == 0 {
                        ForEach(history) { item in
                            PaletteSummary(title: historyTitle(item.colors), colors: item.colors) {
                                input = item.colors.map { "\($0.name) \($0.hex)" }.joined(separator: "\n")
                            }
                        }
                    } else if selectedTab == 1 {
                        ForEach(savedColors) { item in
                            ColorRow(item: ColorItem(name: item.name, hex: item.hex), buttonTitle: "載入") {
                                input = "\(item.name) \(item.hex)"
                            }
                        }
                    } else {
                        ForEach(savedPalettes) { palette in
                            PaletteSummary(title: palette.name, colors: palette.colors) {
                                input = palette.colors.map { "\($0.name) \($0.hex)" }.joined(separator: "\n")
                            }
                        }
                    }
                } header: {
                    Text("歷史與收藏")
                }
            }
            .navigationTitle("Hex 顏色")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(session == nil ? "登入 / 註冊" : session?.email ?? "帳號") {
                        showAccount = true
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(.bar)
            }
            .sheet(isPresented: $showAccount) {
                accountView
                    .presentationDetents([.medium])
            }
            .task {
                importSharedPalettes()
                recordHistory()
                if session != nil {
                    await syncFromCloud()
                }
            }
        }
    }

    private var accountView: some View {
        NavigationStack {
            Form {
                if let session {
                    Section("目前帳號") {
                        Text(session.email)
                        Button("同步雲端") {
                            Task { await syncToCloud() }
                        }
                        Button("登出", role: .destructive) {
                            self.session = nil
                            Store.saveSession(nil)
                            message = "已登出，接下來使用本機儲存"
                            showAccount = false
                        }
                    }
                } else {
                    Section("帳號同步") {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        SecureField("密碼", text: $password)
                            .textContentType(.password)
                        Button("登入") {
                            Task { await authenticate(create: false) }
                        }
                        Button("建立帳號") {
                            Task { await authenticate(create: true) }
                        }
                    }
                    Text("登入後會把這台 iPhone 的色票合併到 Firebase，網站版也能讀到。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("帳號")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { showAccount = false }
                }
            }
        }
    }

    private func saveColor(_ item: ColorItem) {
        let saved = SavedColor(id: makeId(), name: item.name, hex: item.hex, createdAt: now())
        savedColors.insert(saved, at: 0)
        Store.save(savedColors, key: "savedColors")
        selectedTab = 1
        message = "已收藏 \(item.name)"
        Task { await syncToCloud() }
    }

    private func savePalette() {
        let colors = parsedColors
        guard !colors.isEmpty else { return }
        let palette = ColorPalette(id: makeId(), name: defaultPaletteName(colors), createdAt: now(), colors: colors)
        savedPalettes.insert(palette, at: 0)
        Store.save(savedPalettes, key: "savedPalettes")
        selectedTab = 2
        message = "已儲存色系 \(palette.name)"
        Task { await syncToCloud() }
    }

    private func recordHistory() {
        let colors = parsedColors
        guard !colors.isEmpty else { return }
        let signature = colors.map(\.hex).joined(separator: "|")
        if history.first?.signature == signature { return }
        history.insert(HistoryItem(id: makeId(), signature: signature, createdAt: now(), colors: colors), at: 0)
        history = Array(history.prefix(24))
        Store.save(history, key: "history")
    }

    private func importSharedPalettes() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: sharedImportKey),
              let imported = try? JSONDecoder().decode([ColorPalette].self, from: data),
              !imported.isEmpty else {
            return
        }

        savedPalettes = merge(savedPalettes, imported)
        Store.save(savedPalettes, key: "savedPalettes")
        defaults.removeObject(forKey: sharedImportKey)
        selectedTab = 2
        message = "已匯入 \(imported.count) 組分享色系"
        Task { await syncToCloud() }
    }

    private func authenticate(create: Bool) async {
        guard !email.isEmpty, password.count >= 6 else {
            message = "請輸入 Email，密碼至少 6 個字"
            return
        }

        do {
            message = create ? "正在建立帳號..." : "正在登入..."
            let session = try await FirebaseClient.authenticate(email: email, password: password, create: create)
            self.session = session
            Store.saveSession(session)
            password = ""
            showAccount = false
            await syncFromCloud()
        } catch {
            message = "帳號操作失敗，請稍後再試"
        }
    }

    private func syncFromCloud() async {
        guard let session else { return }
        do {
            message = "讀取雲端..."
            let remoteHistory: [HistoryItem] = try await FirebaseClient.fetch("history", session: session)
            let remoteColors: [SavedColor] = try await FirebaseClient.fetch("savedColors", session: session)
            let remotePalettes: [ColorPalette] = try await FirebaseClient.fetch("savedPalettes", session: session)

            history = merge(history, remoteHistory).prefixArray(24)
            savedColors = merge(savedColors, remoteColors)
            savedPalettes = merge(savedPalettes, remotePalettes)
            Store.save(history, key: "history")
            Store.save(savedColors, key: "savedColors")
            Store.save(savedPalettes, key: "savedPalettes")
            await syncToCloud()
        } catch {
            message = "雲端讀取失敗"
        }
    }

    private func syncToCloud() async {
        guard let session else { return }
        do {
            message = "同步中..."
            try await FirebaseClient.upload(history, collection: "history", session: session)
            try await FirebaseClient.upload(savedColors, collection: "savedColors", session: session)
            try await FirebaseClient.upload(savedPalettes, collection: "savedPalettes", session: session)
            message = "已同步"
        } catch {
            message = "雲端同步失敗"
        }
    }
}

struct ColorRow: View {
    var item: ColorItem
    var buttonTitle = "收藏"
    var action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8)
                .fill(item.swiftColor)
                .frame(width: 58, height: 58)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black.opacity(0.08)))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.headline)
                Text(item.hex).font(.system(.subheadline, design: .monospaced))
                Text(rgbText(item.hex)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
        }
    }
}

struct PaletteSummary: View {
    var title: String
    var colors: [ColorItem]
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline).foregroundStyle(.primary)
                HStack(spacing: 0) {
                    ForEach(colors) { item in
                        Rectangle().fill(item.swiftColor)
                    }
                }
                .frame(height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Text("\(colors.count) 個顏色")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

enum ColorParser {
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

enum FirebaseClient {
    static func authenticate(email: String, password: String, create: Bool) async throws -> AuthSession {
        let method = create ? "signUp" : "signInWithPassword"
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:\(method)?key=\(firebaseApiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
            "returnSecureToken": true
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.userAuthenticationRequired) }
        let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)
        return AuthSession(email: decoded.email, localId: decoded.localId, idToken: decoded.idToken)
    }

    static func upload<T: Codable & Identifiable>(_ items: [T], collection: String, session: AuthSession) async throws where T.ID == String {
        for item in items {
            let url = firestoreURL("users/\(session.localId)/\(collection)/\(item.id)")
            var request = authorizedRequest(url, session: session)
            request.httpMethod = "PATCH"
            request.httpBody = try FirestoreCodec.documentData(for: item)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard [200, 201].contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
                throw URLError(.cannotWriteToFile)
            }
        }
    }

    static func fetch<T: Decodable>(_ collection: String, session: AuthSession) async throws -> [T] {
        let url = firestoreURL("users/\(session.localId)/\(collection)")
        let request = authorizedRequest(url, session: session)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return [] }
        guard status == 200 else { throw URLError(.badServerResponse) }
        return try FirestoreCodec.decodeList(T.self, from: data)
    }

    private static func firestoreURL(_ path: String) -> URL {
        URL(string: "https://firestore.googleapis.com/v1/projects/\(firebaseProjectId)/databases/(default)/documents/\(path)")!
    }

    private static func authorizedRequest(_ url: URL, session: AuthSession) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(session.idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
}

struct AuthResponse: Codable {
    var email: String
    var localId: String
    var idToken: String
}

enum FirestoreCodec {
    static func documentData<T: Codable>(for item: T) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any] ?? [:]
        let fields = object.mapValues(toFirestoreValue)
        return try JSONSerialization.data(withJSONObject: ["fields": fields])
    }

    static func decodeList<T: Decodable>(_ type: T.Type, from data: Data) throws -> [T] {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let docs = root?["documents"] as? [[String: Any]] ?? []
        let objects = docs.compactMap { doc -> [String: Any]? in
            guard let fields = doc["fields"] as? [String: Any] else { return nil }
            return fields.mapValues(fromFirestoreValue)
        }
        let json = try JSONSerialization.data(withJSONObject: objects)
        return try JSONDecoder().decode([T].self, from: json)
    }

    private static func toFirestoreValue(_ value: Any) -> [String: Any] {
        if let value = value as? String { return ["stringValue": value] }
        if let value = value as? Int { return ["integerValue": String(value)] }
        if let value = value as? Int64 { return ["integerValue": String(value)] }
        if let value = value as? Double { return ["doubleValue": value] }
        if let value = value as? Bool { return ["booleanValue": value] }
        if let array = value as? [Any] {
            return ["arrayValue": ["values": array.map(toFirestoreValue)]]
        }
        if let object = value as? [String: Any] {
            return ["mapValue": ["fields": object.mapValues(toFirestoreValue)]]
        }
        return ["nullValue": NSNull()]
    }

    private static func fromFirestoreValue(_ wrapped: Any) -> Any {
        guard let object = wrapped as? [String: Any] else { return NSNull() }
        if let value = object["stringValue"] { return value }
        if let value = object["integerValue"] as? String { return Int64(value) ?? 0 }
        if let value = object["doubleValue"] { return value }
        if let value = object["booleanValue"] { return value }
        if let array = object["arrayValue"] as? [String: Any],
           let values = array["values"] as? [Any] {
            return values.map(fromFirestoreValue)
        }
        if let map = object["mapValue"] as? [String: Any],
           let fields = map["fields"] as? [String: Any] {
            return fields.mapValues(fromFirestoreValue)
        }
        return NSNull()
    }
}

enum Store {
    static func load<T: Decodable>(_ key: String) -> [T] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    static func save<T: Encodable>(_ value: [T], key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }

    static func loadSession() -> AuthSession? {
        guard let data = UserDefaults.standard.data(forKey: "authSession") else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    static func saveSession(_ session: AuthSession?) {
        UserDefaults.standard.set(try? JSONEncoder().encode(session), forKey: "authSession")
    }
}

extension Color {
    init(hex: String) {
        let value = hex.replacingOccurrences(of: "#", with: "")
        let scanner = Scanner(string: value)
        var number: UInt64 = 0
        scanner.scanHexInt64(&number)
        self.init(
            red: Double((number >> 16) & 0xff) / 255,
            green: Double((number >> 8) & 0xff) / 255,
            blue: Double(number & 0xff) / 255
        )
    }
}

private func now() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
}

private func makeId() -> String {
    "\(now())-\(UUID().uuidString.prefix(8))"
}

private func merge<T: Identifiable>(_ local: [T], _ remote: [T]) -> [T] where T.ID == String {
    var map: [String: T] = [:]
    (remote + local).forEach { map[$0.id] = $0 }
    return Array(map.values)
}

private func defaultPaletteName(_ colors: [ColorItem]) -> String {
    colors.prefix(2).map(\.name).joined(separator: "、") + "色系"
}

private func historyTitle(_ colors: [ColorItem]) -> String {
    if colors.count == 1 { return colors[0].name }
    return colors.prefix(2).map(\.name).joined(separator: "、") + "等 \(colors.count) 色"
}

private func rgbText(_ hex: String) -> String {
    let value = hex.replacingOccurrences(of: "#", with: "")
    let scanner = Scanner(string: value)
    var number: UInt64 = 0
    scanner.scanHexInt64(&number)
    return "rgb(\((number >> 16) & 0xff), \((number >> 8) & 0xff), \(number & 0xff))"
}

private func commonName(_ hex: String) -> String {
    [
        "#000000": "黑色", "#333333": "炭黑", "#808080": "灰色",
        "#F6E8C8": "奶油色", "#C9A77B": "奶茶色", "#B94A48": "磚紅",
        "#5F7C69": "鼠尾草綠", "#3B322B": "暖墨色", "#FFFFFF": "白色",
        "#FF0000": "紅色", "#FFD700": "金黃", "#2563EB": "藍色"
    ][hex] ?? "自訂色"
}

private extension Array {
    func prefixArray(_ maxLength: Int) -> [Element] {
        Array(prefix(maxLength))
    }
}
