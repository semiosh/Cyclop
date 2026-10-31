import AppKit
import Combine

@MainActor
final class NotchViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case clipboard, shelf, media, translate, settings
        var id: String { rawValue }
        static let primary: [Tab] = [.clipboard, .shelf, .media, .translate]
        var symbol: String {
            switch self {
            case .clipboard: "list.clipboard"
            case .shelf: "tray.full"
            case .media: "music.note"
            case .translate: "translate"
            case .settings: "gearshape"
            }
        }
        var title: String {
            switch self {
            case .clipboard: localized("Clipboard")
            case .shelf: localized("Shelf")
            case .media: localized("Music")
            case .translate: localized("Translator")
            case .settings: localized("Settings")
            }
        }
        var needsKeyboard: Bool { self == .translate }
        var wantsTallBody: Bool { self == .settings }
        var canHide: Bool { self != .settings }
    }

    private(set) var isPanelActive = false
    var isTyping = false
    @Published private(set) var hiddenTabs: Set<Tab> = Set(ConfigStore.shared.hiddenTabs.compactMap(Tab.init(rawValue:))).filter(\.canHide)
    var primaryTabs: [Tab] { Tab.primary.filter(isVisible) }
    func isVisible(_ tab: Tab) -> Bool { !hiddenTabs.contains(tab) }

    func setVisible(_ target: Tab, _ visible: Bool) {
        guard target.canHide, isVisible(target) != visible else { return }
        if visible {
            hiddenTabs.remove(target)
            if started { startBackground(of: target) }
        } else {
            hiddenTabs.insert(target)
            stopBackground(of: target)
            if tab == target { tab = primaryTabs.first ?? .settings }
        }
        ConfigStore.shared.hiddenTabs = hiddenTabs.map(\.rawValue).sorted()
    }

    private func startBackground(of target: Tab) {
        switch target {
        case .media:
            media.start()
            media.setActive(isPanelActive)
        case .clipboard: clipboard.start()
        case .shelf: screenshotFolder.resumeIfEnabled()
        case .translate, .settings: break
        }
    }
    private func stopBackground(of target: Tab) {
        switch target {
        case .media: media.stop()
        case .clipboard: clipboard.stop()
        case .shelf: screenshotFolder.stop()
        case .translate, .settings: break
        }
    }
    func setPanelActive(_ active: Bool) {
        guard active != isPanelActive else { return }
        isPanelActive = active
        if isVisible(.media) { media.setActive(active) }
    }
    private var started = false
    var clickTakesKeyboard: Bool { tab.needsKeyboard || tab == .clipboard }

    @Published var tab: Tab = Tab(rawValue: ConfigStore.shared.lastTool) ?? .clipboard {
        didSet {
            if Tab.primary.contains(tab) { ConfigStore.shared.lastTool = tab.rawValue }
        }
    }

    let media = MediaController()
    let shelf = ShelfStore()
    let clipboard = ClipboardStore(paused: ConfigStore.shared.clipboardPaused)
    let screenshotFolder = ScreenshotFolderWatcher()
    let translator = Translator()
    let privacy = PrivacyMode()
    private var cancellables = Set<AnyCancellable>()

    init() {
        clipboard.retention = ConfigStore.shared.clipboardRetention
        clipboard.onPauseChanged = { ConfigStore.shared.clipboardPaused = $0 }
        // Editors observe their own state so typing does not rebuild the panel.
        for child in [media.objectWillChange, shelf.objectWillChange, clipboard.objectWillChange] {
            child.sink { [weak self] _ in
                guard let self, self.isPanelActive else { return }
                self.objectWillChange.send()
            }.store(in: &cancellables)
        }
    }

    static var saveClipboardImagesEnabled: Bool {
        get { ConfigStore.shared.saveClipboardImages }
        set { ConfigStore.shared.saveClipboardImages = newValue }
    }
    func start() {
        shelf.load()
        clipboard.onImage = { [weak self] png in
            guard Self.saveClipboardImagesEnabled, let self, let url = ScreenshotVault.save(png) else { return }
            self.receivedScreenshot(at: url)
        }
        screenshotFolder.onImage = { [weak self] url in self?.receivedScreenshot(at: url) }
        started = true
        for target in Tab.allCases where isVisible(target) { startBackground(of: target) }
        if !isVisible(tab) { tab = primaryTabs.first ?? .settings }
    }
    func stop() {
        started = false
        for target in Tab.allCases { stopBackground(of: target) }
    }
    func receivedScreenshot(at url: URL) {
        // Collection never changes the user's current tool or keyboard focus.
        shelf.add([url])
    }
    func accept(urls: [URL]) -> Bool {
        guard isVisible(.shelf) else { return false }
        shelf.add(urls)
        tab = .shelf
        return true
    }
    func translate(_ text: String) {
        guard isVisible(.translate) else { return }
        translator.input = text
        tab = .translate
    }
}
