import AppKit
import Translation
import NaturalLanguage

/// Apple Translation only. The visible pane translates after a typing pause.
@MainActor
final class Translator: ObservableObject {
    static let russian = Locale.Language(identifier: "ru")
    static let english = Locale.Language(identifier: "en")
    static let languageCodes = ["ru", "en", "de", "fr", "es", "it", "pt", "uk", "ja", "ko", "zh-Hans"]
    struct Route: Equatable {
        var source: Locale.Language
        var target: Locale.Language
    }
    struct Request: Equatable {
        let text: String
        let route: Route
        let revision: Int
    }
    struct Draft: Equatable {
        let text: String
        let sourceCode: String
        let targetCode: String
    }
    var draft: Draft { Draft(text: input, sourceCode: sourceCode, targetCode: targetCode) }

    /// The view owns this task, so edits restart the delay and leaving the
    /// pane cancels it. Manual requests invalidate a pending automatic one.
    func translateAfterPause(for draft: Draft, delay: Duration = .milliseconds(350)) async {
        guard !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let currentRevision = revision
        do { try await Task.sleep(for: delay) } catch { return }
        guard !Task.isCancelled, self.draft == draft, revision == currentRevision else { return }
        requestTranslation()
    }

    @Published var input = "" { didSet { if input != oldValue { invalidate() } } }
    @Published var sourceCode = "auto" { didSet { if sourceCode != oldValue { invalidate() } } }
    @Published var targetCode: String {
        didSet {
            if targetCode != oldValue {
                persistTarget(targetCode)
                invalidate()
            }
        }
    }
    @Published private(set) var output = ""
    @Published private(set) var failure: String?
    @Published private(set) var needsDownload = false
    @Published private(set) var isTranslating = false
    @Published private(set) var request: Request?
    private var revision = 0
    private let persistTarget: (String) -> Void
    var trimmed: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }
    var route: Route {
        let automatic = Self.route(for: trimmed)
        let source = sourceCode == "auto" ? automatic.source : Locale.Language(identifier: sourceCode)
        let target = targetCode == "auto"
            ? (source.languageCode?.identifier == "ru" ? Self.english : Self.russian)
            : Locale.Language(identifier: targetCode)
        return Route(source: source, target: target)
    }
    init(targetCode: String? = nil, persistTarget: @escaping (String) -> Void = { ConfigStore.shared.translationTarget = $0 }) {
        self.persistTarget = persistTarget
        let stored = targetCode ?? ConfigStore.shared.translationTarget
        self.targetCode = Self.languageCodes.contains(stored) ? stored : "auto"
    }
    static func route(for text: String) -> Route {
        // Short Cyrillic words are often misidentified as Bulgarian. Keep the
        // original RU/EN shortcut for those and recognize longer passages.
        let cyrillic = text.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
        let detected = text.count < 20 && cyrillic ? "ru" : NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
        let source = Locale.Language(identifier: detected ?? (cyrillic ? "ru" : "en"))
        return Route(source: source, target: source.languageCode?.identifier == "ru" ? english : russian)
    }
    private func invalidate() {
        revision += 1
        request = nil
        clear()
    }
    func clear() {
        output = ""; failure = nil; needsDownload = false; isTranslating = false
    }
    func reset() { input = ""; invalidate() }
    func requestTranslation() {
        guard !trimmed.isEmpty else { return }
        revision += 1
        clear()
        let route = route
        if route.source.languageCode == route.target.languageCode {
            output = trimmed
            request = nil
            return
        }
        isTranslating = true
        request = Request(text: trimmed, route: route, revision: revision)
    }
    func retry() { requestTranslation() }
    func swapLanguages() {
        let old = route
        let translated = output
        sourceCode = old.target.languageCode?.identifier ?? "en"
        targetCode = old.source.languageCode?.identifier ?? "ru"
        if !translated.isEmpty { input = translated }
    }
    func pasteInput() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        input = text
    }
    func run(_ session: sending TranslationSession) async {
        guard let pending = request,
              session.sourceLanguage == pending.route.source,
              session.targetLanguage == pending.route.target else { return }
        let status = await LanguageAvailability().status(from: pending.route.source, to: pending.route.target)
        guard request == pending, !Task.isCancelled else { return }
        guard status == .installed else {
            isTranslating = false
            needsDownload = status == .supported
            failure = needsDownload
                ? localized("The %@ → %@ language pack is not installed.", Self.name(pending.route.source), Self.name(pending.route.target))
                : localized("macOS does not translate this pair of languages.")
            return
        }
        do {
            let response = try await session.translate(pending.text)
            guard request == pending, !Task.isCancelled else { return }
            output = response.targetText
            isTranslating = false
        } catch {
            guard request == pending, !Task.isCancelled else { return }
            isTranslating = false
            needsDownload = false
            failure = error.localizedDescription
        }
    }
    func copyOutput() {
        guard !output.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
    }
    static func name(_ language: Locale.Language) -> String {
        guard let code = language.languageCode?.identifier,
              let name = Locale(identifier: appLanguage).localizedString(forLanguageCode: code) else {
            return language.languageCode?.identifier.uppercased() ?? "?"
        }
        return name.prefix(1).uppercased() + name.dropFirst()
    }
    static func openLanguageSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
