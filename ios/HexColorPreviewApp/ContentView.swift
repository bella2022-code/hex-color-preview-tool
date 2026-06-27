import SwiftUI
import UIKit

private let firebaseApiKey = "AIzaSyB6624vmNjfIbrQ6WZZesLxgDps3LwT_BM"
private let firebaseProjectId = "hex-color-preview-tool"
private let appGroupIdentifier = "group.com.chartgreen.hexcolorpreview"
private let sharedImportKey = "sharedImportedPalettes"
private let sharedPendingKey = "sharedPendingPalettes"

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
    var refreshToken: String?
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
    @State private var showPassword = false
    @State private var message = "本機儲存"
    @State private var showAccount = false
    @State private var selectedTab = 0
    @State private var searchQuery = ""
    @State private var renameTarget: RenameTarget?
    @State private var renameText = ""
    @State private var deleteTarget: DeleteTarget?
    @State private var pendingSharedPalettes: [ColorPalette] = []
    @State private var showSharedImport = false
    @State private var selectedMode = 0
    @State private var pickedImage: UIImage?
    @State private var imagePalette: [ColorItem] = []
    @State private var showImagePicker = false
    @State private var imageSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var manualColor = Color(hex: "#C9A77B")
    @State private var manualColorName = "手動調色"

    private var parsedColors: [ColorItem] {
        ColorParser.parse(input)
    }

    private var recommendedPalettes: [ColorPalette] {
        RecommendationLibrary.palettes
    }

    private var manualColorHex: String {
        manualColor.hexString
    }

    private var manualColorItem: ColorItem {
        let name = manualColorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return ColorItem(name: name.isEmpty ? commonName(manualColorHex) : name, hex: manualColorHex)
    }

    private var filteredSavedColors: [SavedColor] {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return savedColors
        }
        return savedColors.filter { matchesSearch([$0.name, $0.hex]) }
    }

    private var filteredSavedPalettes: [ColorPalette] {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return savedPalettes
        }
        return savedPalettes.filter { palette in
            matchesSearch([palette.name] + palette.colors.flatMap { [$0.name, $0.hex] })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("模式", selection: $selectedMode) {
                        Text("輸入").tag(0)
                        Text("截圖/拍照").tag(1)
                        Text("靈感").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                if selectedMode == 0 {
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

                    manualColorSection
                } else if selectedMode == 1 {
                    imagePickerSection
                } else {
                    recommendationSection
                }

                Section {
                    Picker("收藏", selection: $selectedTab) {
                        Text("歷史").tag(0)
                        Text("單色").tag(1)
                        Text("色系").tag(2)
                    }
                    .pickerStyle(.segmented)

                    if selectedTab != 0 {
                        TextField("搜尋名稱或 Hex", text: $searchQuery)
                            .textInputAutocapitalization(.never)
                    }

                    if selectedTab == 0 {
                        ForEach(history) { item in
                            PaletteSummary(title: historyTitle(item.colors), colors: item.colors) {
                                input = item.colors.map { "\($0.name) \($0.hex)" }.joined(separator: "\n")
                            }
                        }
                    } else if selectedTab == 1 {
                        ForEach(filteredSavedColors) { item in
                            HStack(spacing: 8) {
                                ColorRow(item: ColorItem(name: item.name, hex: item.hex), buttonTitle: "載入") {
                                    input = "\(item.name) \(item.hex)"
                                }

                                Button(role: .destructive) {
                                    deleteTarget = .color(item)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("刪除單色")
                            }
                            .contextMenu {
                                Button("重新命名") { startRename(.color(item)) }
                                Button("刪除", role: .destructive) { deleteTarget = .color(item) }
                            }
                            .swipeActions {
                                Button("刪除", role: .destructive) { deleteTarget = .color(item) }
                                Button("重新命名") { startRename(.color(item)) }
                                    .tint(.blue)
                            }
                        }
                    } else {
                        ForEach(filteredSavedPalettes) { palette in
                            HStack(spacing: 8) {
                                PaletteSummary(title: palette.name, colors: palette.colors) {
                                    input = palette.colors.map { "\($0.name) \($0.hex)" }.joined(separator: "\n")
                                }

                                Button(role: .destructive) {
                                    deleteTarget = .palette(palette)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("刪除色系")
                            }
                            .contextMenu {
                                Button("重新命名") { startRename(.palette(palette)) }
                                Button("刪除", role: .destructive) { deleteTarget = .palette(palette) }
                            }
                            .swipeActions {
                                Button("刪除", role: .destructive) { deleteTarget = .palette(palette) }
                                Button("重新命名") { startRename(.palette(palette)) }
                                    .tint(.blue)
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
            .sheet(item: $renameTarget) { target in
                renameView(target)
                    .presentationDetents([.height(220)])
            }
            .sheet(isPresented: $showSharedImport) {
                sharedImportView
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(sourceType: imageSource) { image in
                    handlePickedImage(image)
                }
            }
            .alert("刪除收藏？", isPresented: deleteAlertBinding) {
                Button("取消", role: .cancel) { deleteTarget = nil }
                Button("刪除", role: .destructive) { confirmDelete() }
            } message: {
                Text(deleteTarget?.title ?? "")
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

    private var imagePickerSection: some View {
        Group {
            Section("圖片取色") {
                VStack(spacing: 10) {
                    Button {
                        imageSource = .photoLibrary
                        showImagePicker = true
                    } label: {
                        Label("從截圖或照片選擇", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            imageSource = .camera
                            showImagePicker = true
                        } label: {
                            Label("打開相機拍照", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let pickedImage {
                    TappableImage(image: pickedImage) { location, size in
                        addTappedColor(from: pickedImage, location: location, canvasSize: size)
                    }
                    .frame(minHeight: 220)
                } else {
                    ContentUnavailableView("還沒有圖片", systemImage: "photo.on.rectangle", description: Text("選擇截圖或拍攝物體後，會自動抓出主要色系。"))
                }
            }

            if !imagePalette.isEmpty {
                Section("偵測到的色系") {
                    PaletteSummary(title: "圖片色系", colors: imagePalette) {
                        input = imagePalette.map { "\($0.name) \($0.hex)" }.joined(separator: "\n")
                        selectedMode = 0
                    }

                    ForEach(imagePalette) { item in
                        ColorRow(item: item) {
                            saveColor(item)
                        }
                    }

                    Button("儲存圖片色系") {
                        savePalette(imagePalette, name: "圖片擷取色系")
                    }
                    .disabled(imagePalette.isEmpty)
                }
            }
        }
    }

    private var manualColorSection: some View {
        Section("手動調色") {
            ColorPicker("色環", selection: $manualColor, supportsOpacity: false)

            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(manualColor)
                    .frame(width: 58, height: 58)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black.opacity(0.08)))

                VStack(alignment: .leading, spacing: 4) {
                    TextField("顏色名稱", text: $manualColorName)
                        .textInputAutocapitalization(.words)
                    Text(manualColorHex)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button {
                    appendManualColorToInput()
                } label: {
                    Label("加入輸入", systemImage: "plus")
                }

                Spacer()

                Button {
                    saveColor(manualColorItem)
                } label: {
                    Label("收藏單色", systemImage: "bookmark")
                }
            }
        }
    }

    private var recommendationSection: some View {
        Section("推薦色系") {
            ForEach(recommendedPalettes) { palette in
                PaletteSummary(title: palette.name, colors: palette.colors) {
                    input = palette.colors.map { "\($0.name) \($0.hex)" }.joined(separator: "\n")
                    selectedMode = 0
                    recordHistory()
                }
                .contextMenu {
                    Button("儲存色系") {
                        savePalette(palette.colors, name: palette.name)
                    }
                }

                Button {
                    savePalette(palette.colors, name: palette.name)
                } label: {
                    Label("儲存 \(palette.name)", systemImage: "bookmark")
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
                        HStack {
                            Group {
                                if showPassword {
                                    TextField("密碼", text: $password)
                                } else {
                                    SecureField("密碼", text: $password)
                                }
                            }
                            .textContentType(.password)

                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(showPassword ? "隱藏密碼" : "顯示密碼")
                        }
                        Button("登入") {
                            Task { await authenticate(create: false) }
                        }
                        Button("建立帳號") {
                            Task { await authenticate(create: true) }
                        }
                        Button("忘記密碼") {
                            Task { await resetPassword() }
                        }
                        .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private func renameView(_ target: RenameTarget) -> some View {
        NavigationStack {
            Form {
                TextField("名稱", text: $renameText)
                    .textInputAutocapitalization(.words)
            }
            .navigationTitle("重新命名")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { renameTarget = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { confirmRename(target) }
                        .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var sharedImportView: some View {
        NavigationStack {
            List {
                Section("分享偵測到的色系") {
                    ForEach(pendingSharedPalettes) { palette in
                        PaletteSummary(title: palette.name, colors: palette.colors) {
                            input = palette.colors.map { "\($0.name) \($0.hex)" }.joined(separator: "\n")
                        }
                    }
                }
            }
            .navigationTitle("確認儲存")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("略過") {
                        pendingSharedPalettes = []
                        showSharedImport = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("全部儲存") { confirmSharedImport() }
                        .disabled(pendingSharedPalettes.isEmpty)
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
        savePalette(colors, name: defaultPaletteName(colors))
    }

    private func savePalette(_ colors: [ColorItem], name: String) {
        guard !colors.isEmpty else { return }
        let palette = ColorPalette(id: makeId(), name: name, createdAt: now(), colors: colors)
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
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }

        if let data = defaults.data(forKey: sharedPendingKey),
           let pending = try? JSONDecoder().decode([ColorPalette].self, from: data),
           !pending.isEmpty {
            pendingSharedPalettes = pending
            defaults.removeObject(forKey: sharedPendingKey)
            showSharedImport = true
            message = "分享偵測到 \(pending.count) 組色系"
        }

        if let data = defaults.data(forKey: sharedImportKey),
           let imported = try? JSONDecoder().decode([ColorPalette].self, from: data),
           !imported.isEmpty {
            savedPalettes = merge(savedPalettes, imported)
            Store.save(savedPalettes, key: "savedPalettes")
            defaults.removeObject(forKey: sharedImportKey)
            selectedTab = 2
            message = "已匯入 \(imported.count) 組分享色系"
            Task { await syncToCloud() }
        }
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
            message = accountMessage(for: error)
        }
    }

    private func resetPassword() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            message = "請先輸入 Email"
            return
        }

        do {
            message = "正在寄出重設信..."
            try await FirebaseClient.resetPassword(email: trimmedEmail)
            message = "已寄出密碼重設信"
        } catch {
            message = accountMessage(for: error)
        }
    }

    private func syncFromCloud() async {
        guard let session else { return }
        do {
            message = "讀取雲端..."
            let activeSession = try await refreshSessionIfNeeded(session)
            let remoteHistory: [HistoryItem] = try await FirebaseClient.fetch("history", session: activeSession)
            let remoteColors: [SavedColor] = try await FirebaseClient.fetch("savedColors", session: activeSession)
            let remotePalettes: [ColorPalette] = try await FirebaseClient.fetch("savedPalettes", session: activeSession)

            history = merge(history, remoteHistory).prefixArray(24)
            savedColors = merge(savedColors, remoteColors)
            savedPalettes = merge(savedPalettes, remotePalettes)
            Store.save(history, key: "history")
            Store.save(savedColors, key: "savedColors")
            Store.save(savedPalettes, key: "savedPalettes")
            await syncToCloud()
        } catch {
            message = cloudMessage(prefix: "雲端讀取失敗", error: error)
        }
    }

    private func syncToCloud() async {
        guard let session else { return }
        do {
            message = "同步中..."
            let activeSession = try await refreshSessionIfNeeded(session)
            try await FirebaseClient.upload(history, collection: "history", session: activeSession)
            try await FirebaseClient.upload(savedColors, collection: "savedColors", session: activeSession)
            try await FirebaseClient.upload(savedPalettes, collection: "savedPalettes", session: activeSession)
            message = "已同步"
        } catch {
            message = cloudMessage(prefix: "雲端同步失敗", error: error)
        }
    }

    private func refreshSessionIfNeeded(_ session: AuthSession) async throws -> AuthSession {
        let refreshed = try await FirebaseClient.refresh(session)
        self.session = refreshed
        Store.saveSession(refreshed)
        return refreshed
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private func startRename(_ target: RenameTarget) {
        renameText = target.title
        renameTarget = target
    }

    private func confirmRename(_ target: RenameTarget) {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        switch target {
        case .color(let item):
            guard let index = savedColors.firstIndex(where: { $0.id == item.id }) else { return }
            savedColors[index].name = name
            Store.save(savedColors, key: "savedColors")
            message = "已重新命名單色"
        case .palette(let item):
            guard let index = savedPalettes.firstIndex(where: { $0.id == item.id }) else { return }
            savedPalettes[index].name = name
            Store.save(savedPalettes, key: "savedPalettes")
            message = "已重新命名色系"
        }

        renameTarget = nil
        Task { await syncToCloud() }
    }

    private func confirmDelete() {
        guard let deleteTarget else { return }

        switch deleteTarget {
        case .color(let item):
            savedColors.removeAll { $0.id == item.id }
            Store.save(savedColors, key: "savedColors")
            message = "已刪除單色"
            Task { await deleteRemote("savedColors", id: item.id) }
        case .palette(let item):
            savedPalettes.removeAll { $0.id == item.id }
            Store.save(savedPalettes, key: "savedPalettes")
            message = "已刪除色系"
            Task { await deleteRemote("savedPalettes", id: item.id) }
        }

        self.deleteTarget = nil
    }

    private func deleteRemote(_ collection: String, id: String) async {
        guard let session else { return }
        do {
            let activeSession = try await refreshSessionIfNeeded(session)
            try await FirebaseClient.delete(collection, id: id, session: activeSession)
        } catch {
            message = cloudMessage(prefix: "雲端刪除失敗", error: error)
        }
    }

    private func confirmSharedImport() {
        savedPalettes = merge(savedPalettes, pendingSharedPalettes)
        Store.save(savedPalettes, key: "savedPalettes")
        selectedTab = 2
        message = "已儲存分享色系"
        pendingSharedPalettes = []
        showSharedImport = false
        Task { await syncToCloud() }
    }

    private func matchesSearch(_ values: [String]) -> Bool {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return values.contains { $0.lowercased().contains(query) }
    }

    private func handlePickedImage(_ image: UIImage) {
        pickedImage = image
        imagePalette = image.extractedPalette(maxColors: 6)
        message = imagePalette.isEmpty ? "沒有偵測到色彩" : "已抓出 \(imagePalette.count) 個圖片顏色"
    }

    private func addTappedColor(from image: UIImage, location: CGPoint, canvasSize: CGSize) {
        guard let hex = image.hexColor(at: location, canvasSize: canvasSize) else {
            message = "點的位置不在圖片上"
            return
        }

        let color = ColorItem(name: "點選色 \(imagePalette.count + 1)", hex: hex)
        imagePalette.removeAll { $0.hex == hex }
        imagePalette.insert(color, at: 0)
        imagePalette = Array(imagePalette.prefix(8))
        message = "已加入 \(hex)"
    }

    private func appendManualColorToInput() {
        let item = manualColorItem
        let line = "\(item.name) \(item.hex)"
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        input = trimmed.isEmpty ? line : "\(trimmed)\n\(line)"
        recordHistory()
        message = "已加入 \(item.hex)"
    }
}

enum RenameTarget: Identifiable {
    case color(SavedColor)
    case palette(ColorPalette)

    var id: String {
        switch self {
        case .color(let item): "color-\(item.id)"
        case .palette(let item): "palette-\(item.id)"
        }
    }

    var title: String {
        switch self {
        case .color(let item): item.name
        case .palette(let item): item.name
        }
    }
}

enum DeleteTarget {
    case color(SavedColor)
    case palette(ColorPalette)

    var title: String {
        switch self {
        case .color(let item): "\(item.name) \(item.hex)"
        case .palette(let item): "\(item.name)，共 \(item.colors.count) 個顏色"
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    var onImagePicked: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker

        init(parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct TappableImage: View {
    var image: UIImage
    var onTap: (CGPoint, CGSize) -> Void

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black.opacity(0.08)))
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            onTap(value.location, proxy.size)
                        }
                )
        }
        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
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

enum RecommendationLibrary {
    static let palettes: [ColorPalette] = [
        palette("2026 熱門靈感", [
            ("Transformative Teal", "#4F8F8B"),
            ("Electric Fuchsia", "#D946EF"),
            ("Soft Butter", "#F4D06F"),
            ("Digital Lavender", "#B8A4E3"),
            ("Grounded Cocoa", "#6E5144")
        ]),
        palette("維多利亞壁紙", [
            ("Dusty Rose", "#B77A7A"),
            ("Aged Gold", "#B89B5E"),
            ("Moss Damask", "#596B4F"),
            ("Faded Cream", "#E8D9B5"),
            ("Ink Vine", "#2F3430")
        ]),
        palette("馬卡龍", [
            ("Pistachio", "#BFE3C0"),
            ("Strawberry Milk", "#F6B7C8"),
            ("Vanilla Cream", "#F7E7B7"),
            ("Blueberry Foam", "#B8D7F3"),
            ("Lavender Sugar", "#D9C7EF")
        ]),
        palette("森林", [
            ("Pine Shadow", "#1F3D2B"),
            ("Fern", "#5E8C61"),
            ("Moss", "#8EA66A"),
            ("Bark", "#6B5142"),
            ("Mist", "#D7DDCF")
        ]),
        palette("奶茶日常", [
            ("Oat Milk", "#E9D9C1"),
            ("Milk Tea", "#C9A77B"),
            ("Caramel", "#B98555"),
            ("Warm Ink", "#3B322B"),
            ("Porcelain", "#F7F2EA")
        ])
    ]

    private static func palette(_ name: String, _ values: [(String, String)]) -> ColorPalette {
        ColorPalette(
            id: "recommendation-\(name)",
            name: name,
            createdAt: 0,
            colors: values.map { ColorItem(name: $0.0, hex: $0.1) }
        )
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
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw firebaseError(from: data)
        }
        let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)
        return AuthSession(
            email: decoded.email,
            localId: decoded.localId,
            idToken: decoded.idToken,
            refreshToken: decoded.refreshToken
        )
    }

    static func refresh(_ session: AuthSession) async throws -> AuthSession {
        guard let refreshToken = session.refreshToken, !refreshToken.isEmpty else {
            throw FirebaseAuthError(code: "MISSING_REFRESH_TOKEN")
        }

        let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(firebaseApiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let encodedToken = refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? refreshToken
        let body = "grant_type=refresh_token&refresh_token=\(encodedToken)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw firebaseError(from: data)
        }

        let decoded = try JSONDecoder().decode(TokenRefreshResponse.self, from: data)
        return AuthSession(
            email: session.email,
            localId: decoded.userId,
            idToken: decoded.idToken,
            refreshToken: decoded.refreshToken
        )
    }

    static func resetPassword(email: String) async throws {
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=\(firebaseApiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "requestType": "PASSWORD_RESET",
            "email": email
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw firebaseError(from: data)
        }
    }

    static func upload<T: Codable & Identifiable>(_ items: [T], collection: String, session: AuthSession) async throws where T.ID == String {
        for item in items {
            let url = firestoreURL("users/\(session.localId)/\(collection)/\(item.id)")
            var request = authorizedRequest(url, session: session)
            request.httpMethod = "PATCH"
            request.httpBody = try FirestoreCodec.documentData(for: item)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard [200, 201].contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
                throw firebaseError(from: data)
            }
        }
    }

    static func fetch<T: Decodable>(_ collection: String, session: AuthSession) async throws -> [T] {
        let url = firestoreURL("users/\(session.localId)/\(collection)")
        let request = authorizedRequest(url, session: session)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return [] }
        guard status == 200 else { throw firebaseError(from: data) }
        return try FirestoreCodec.decodeList(T.self, from: data)
    }

    static func delete(_ collection: String, id: String, session: AuthSession) async throws {
        let url = firestoreURL("users/\(session.localId)/\(collection)/\(id)")
        var request = authorizedRequest(url, session: session)
        request.httpMethod = "DELETE"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard [200, 404].contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
            throw firebaseError(from: data)
        }
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

    private static func firebaseError(from data: Data) -> Error {
        if let decoded = try? JSONDecoder().decode(FirebaseErrorResponse.self, from: data) {
            return FirebaseAuthError(code: decoded.error.message)
        }
        return URLError(.badServerResponse)
    }
}

struct AuthResponse: Codable {
    var email: String
    var localId: String
    var idToken: String
    var refreshToken: String
}

struct TokenRefreshResponse: Codable {
    var userId: String
    var idToken: String
    var refreshToken: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case idToken = "id_token"
        case refreshToken = "refresh_token"
    }
}

struct FirebaseErrorResponse: Codable {
    struct Body: Codable {
        var message: String
    }

    var error: Body
}

struct FirebaseAuthError: LocalizedError {
    var code: String
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

    var hexString: String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#000000"
        }

        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}

private extension UIImage {
    func extractedPalette(maxColors: Int) -> [ColorItem] {
        guard let cgImage = renderedCGImage(size: CGSize(width: 88, height: 88)),
              let data = rgbaData(from: cgImage) else {
            return []
        }

        var buckets: [String: (count: Int, red: Int, green: Int, blue: Int)] = [:]
        let width = cgImage.width
        let height = cgImage.height

        for index in stride(from: 0, to: width * height * 4, by: 4) {
            let red = Int(data[index])
            let green = Int(data[index + 1])
            let blue = Int(data[index + 2])
            let alpha = Int(data[index + 3])

            if alpha < 180 { continue }
            if red + green + blue < 48 { continue }
            if red + green + blue > 735 { continue }

            let bucketRed = (red / 24) * 24
            let bucketGreen = (green / 24) * 24
            let bucketBlue = (blue / 24) * 24
            let key = "\(bucketRed)-\(bucketGreen)-\(bucketBlue)"
            let current = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (
                current.count + 1,
                current.red + red,
                current.green + green,
                current.blue + blue
            )
        }

        var selected: [(red: Int, green: Int, blue: Int)] = []
        for bucket in buckets.values.sorted(by: { $0.count > $1.count }) {
            let color = (
                red: bucket.red / max(bucket.count, 1),
                green: bucket.green / max(bucket.count, 1),
                blue: bucket.blue / max(bucket.count, 1)
            )

            guard selected.allSatisfy({ colorDistance(color, $0) > 44 }) else {
                continue
            }

            selected.append(color)
            if selected.count == maxColors { break }
        }

        return selected.enumerated().map { index, color in
            ColorItem(name: "圖片色 \(index + 1)", hex: hex(red: color.red, green: color.green, blue: color.blue))
        }
    }

    func hexColor(at location: CGPoint, canvasSize: CGSize) -> String? {
        guard size.width > 0, size.height > 0, canvasSize.width > 0, canvasSize.height > 0 else {
            return nil
        }

        let imageAspect = size.width / size.height
        let canvasAspect = canvasSize.width / canvasSize.height
        let fittedSize: CGSize
        if imageAspect > canvasAspect {
            fittedSize = CGSize(width: canvasSize.width, height: canvasSize.width / imageAspect)
        } else {
            fittedSize = CGSize(width: canvasSize.height * imageAspect, height: canvasSize.height)
        }

        let origin = CGPoint(
            x: (canvasSize.width - fittedSize.width) / 2,
            y: (canvasSize.height - fittedSize.height) / 2
        )
        let fittedRect = CGRect(origin: origin, size: fittedSize)
        guard fittedRect.contains(location) else { return nil }

        let relativeX = (location.x - origin.x) / fittedSize.width
        let relativeY = (location.y - origin.y) / fittedSize.height
        let renderSize = CGSize(width: max(size.width, 1), height: max(size.height, 1))

        guard let cgImage = renderedCGImage(size: renderSize),
              let data = rgbaData(from: cgImage) else {
            return nil
        }

        let x = min(max(Int(relativeX * CGFloat(cgImage.width)), 0), cgImage.width - 1)
        let y = min(max(Int(relativeY * CGFloat(cgImage.height)), 0), cgImage.height - 1)
        let index = (y * cgImage.width + x) * 4
        return hex(red: Int(data[index]), green: Int(data[index + 1]), blue: Int(data[index + 2]))
    }

    private func renderedCGImage(size targetSize: CGSize) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            draw(in: CGRect(origin: .zero, size: targetSize))
        }.cgImage
    }

    private func rgbaData(from cgImage: CGImage) -> [UInt8]? {
        let width = cgImage.width
        let height = cgImage.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    private func hex(red: Int, green: Int, blue: Int) -> String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    private func colorDistance(_ lhs: (red: Int, green: Int, blue: Int), _ rhs: (red: Int, green: Int, blue: Int)) -> Double {
        let red = Double(lhs.red - rhs.red)
        let green = Double(lhs.green - rhs.green)
        let blue = Double(lhs.blue - rhs.blue)
        return (red * red + green * green + blue * blue).squareRoot()
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

private func accountMessage(for error: Error) -> String {
    guard let error = error as? FirebaseAuthError else {
        return "帳號操作失敗，請稍後再試"
    }

    switch error.code {
    case "EMAIL_EXISTS":
        return "這個 Email 已經註冊過"
    case "EMAIL_NOT_FOUND":
        return "找不到這個 Email"
    case "INVALID_LOGIN_CREDENTIALS", "INVALID_PASSWORD":
        return "Email 或密碼不正確"
    case "WEAK_PASSWORD : Password should be at least 6 characters":
        return "密碼至少要 6 個字"
    case "INVALID_EMAIL":
        return "Email 格式不正確"
    default:
        return "帳號操作失敗：\(error.code)"
    }
}

private func cloudMessage(prefix: String, error: Error) -> String {
    if let error = error as? FirebaseAuthError {
        switch error.code {
        case "MISSING_REFRESH_TOKEN", "TOKEN_EXPIRED", "INVALID_ID_TOKEN", "USER_NOT_FOUND", "INVALID_REFRESH_TOKEN":
            return "\(prefix)：請重新登入一次"
        case let code where code.localizedCaseInsensitiveContains("PERMISSION_DENIED"):
            return "\(prefix)：Firebase 權限未開"
        default:
            return "\(prefix)：\(error.code)"
        }
    }

    if let error = error as? URLError {
        switch error.code {
        case .notConnectedToInternet:
            return "\(prefix)：手機沒有網路"
        case .timedOut:
            return "\(prefix)：連線逾時"
        default:
            return "\(prefix)：網路連線異常"
        }
    }

    return "\(prefix)：請稍後再試"
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
