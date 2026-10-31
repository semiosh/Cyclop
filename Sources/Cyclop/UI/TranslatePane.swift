import SwiftUI
import Translation

struct TranslatePane: View {
    @ObservedObject var translator: Translator
    @Binding var wantsKeyboard: Bool
    @State private var configuration: TranslationSession.Configuration?
    @State private var copied = false

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let column = proxy.size.width / 2
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        HStack(spacing: 6) {
                            languageMenu(source: true)
                            Spacer(minLength: 0)
                            Button { translator.swapLanguages() } label: {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.secondary)
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .help(localized("Swap languages"))
                                .accessibilityLabel(localized("Swap languages"))
                        }
                        .padding(.horizontal, 10)
                        .frame(width: column, height: 30)
                        languageMenu(source: false)
                            .padding(.horizontal, 10)
                            .frame(width: column, height: 30, alignment: .leading)
                    }
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    HStack(spacing: 0) {
                        TranslationEditor(text: $translator.input, wantsKeyboard: $wantsKeyboard,
                                          placeholder: localized("Text to translate"))
                            .frame(width: max(0, column - 0.5))
                        Rectangle().fill(Theme.hairline).frame(width: 1)
                        result
                            .frame(width: max(0, column - 0.5), alignment: .topLeading)
                            .frame(maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                Button { translator.pasteInput(); wantsKeyboard = true } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }.buttonStyle(.plain).foregroundStyle(Theme.secondary)
                if !translator.input.isEmpty {
                    Button { translator.reset() } label: {
                        Image(systemName: "xmark").frame(width: 22, height: 26)
                    }.buttonStyle(.plain).foregroundStyle(Theme.secondary)
                        .accessibilityLabel(localized("Clear"))
                }
                Spacer(minLength: 8)
                Button { translator.copyOutput(); flash($copied) } label: {
                    Label(copied ? localized("Copied") : localized("Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(minWidth: 90)
                }.buttonStyle(.plain)
                    .foregroundStyle(copied ? Color.green : Theme.secondary)
                    .disabled(translator.output.isEmpty)
                    .opacity(translator.output.isEmpty ? 0.35 : 1)
                Button { translator.requestTranslation() } label: {
                    Text(translator.isTranslating ? localized("Translating…") : localized("Translate text"))
                        .lineLimit(1)
                        .frame(width: 94, height: 26)
                        .foregroundStyle(canTranslate ? Color.black : Theme.tertiary)
                        .background(canTranslate ? Color.white.opacity(0.9) : Theme.surface,
                                    in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canTranslate)
            }
            .font(.system(size: 11.5, weight: .medium))
            .frame(height: 28)
            .padding(.horizontal, 2)
        }
        .task(id: translator.draft) {
            await translator.translateAfterPause(for: translator.draft)
        }
        .onChange(of: translator.request) { _, request in
            guard let request else { configuration = nil; return }
            if var current = configuration, current.source == request.route.source, current.target == request.route.target {
                current.invalidate(); configuration = current
            } else {
                configuration = TranslationSession.Configuration(source: request.route.source, target: request.route.target)
            }
        }
        .translationTask(configuration) { session in await translator.run(session) }
    }

    private var canTranslate: Bool { !translator.trimmed.isEmpty && !translator.isTranslating }

    private func languageMenu(source: Bool) -> some View {
        let code = source ? translator.sourceCode : translator.targetCode
        let language = source ? translator.route.source : translator.route.target
        let title = source && code == "auto" && translator.trimmed.isEmpty
            ? localized("Auto") : Translator.name(language)
        return TranslationLanguageMenu(
            selection: source ? $translator.sourceCode : $translator.targetCode,
            title: title,
            automaticTitle: source ? localized("Detect language") : localized("Auto RU ↔ EN"),
            accessibilityTitle: source ? localized("Source language") : localized("Target language")
        )
        .frame(height: 26)
    }

    @ViewBuilder private var result: some View {
        if let failure = translator.failure {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(failure).foregroundStyle(Theme.secondary)
                    if translator.needsDownload {
                        Text("Download the languages once in macOS Settings. Then translation works automatically.")
                            .foregroundStyle(Theme.secondary)
                        Button("Download languages…") { Translator.openLanguageSettings() }.buttonStyle(.plain)
                    } else {
                        Button("Retry") { translator.retry() }.buttonStyle(.plain)
                    }
                }
                .font(.system(size: 11.5)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
        } else if translator.isTranslating {
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini)
                Text("Translating…")
            }.font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(10)
        } else if !translator.output.isEmpty {
            ScrollView(showsIndicators: false) {
                Text(translator.output).font(.system(size: 13)).foregroundStyle(.white)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
        } else {
            Text("Translation").font(.system(size: 13)).foregroundStyle(Theme.tertiary)
                .padding(.horizontal, 10).padding(.vertical, 8)
        }
    }
}

/// Content-sized native menu button. A popup stretched to the whole column
/// sends its arrows to the far edge; here the chevron stays with its title.
private struct TranslationLanguageMenu: NSViewRepresentable {
    @Binding var selection: String
    let title: String
    let automaticTitle: String
    let accessibilityTitle: String

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.isBordered = false
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .medium))
        button.imagePosition = .imageTrailing
        button.alignment = .left
        button.contentTintColor = .labelColor
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.options = [("auto", automaticTitle)] + Translator.languageCodes.map {
            ($0, Translator.name(Locale.Language(identifier: $0)))
        }
        button.title = title
        button.setAccessibilityLabel(accessibilityTitle)
        button.toolTip = accessibilityTitle
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: min(proposal.width ?? .infinity, nsView.intrinsicContentSize.width), height: 26)
    }
    @MainActor final class Coordinator: NSObject {
        var selection: Binding<String>
        var options: [(String, String)] = []
        init(selection: Binding<String>) { self.selection = selection }
        @objc func open(_ sender: NSButton) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for (code, title) in options {
                let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = code
                item.state = selection.wrappedValue == code ? .on : .off
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -3), in: sender)
        }
        @objc func choose(_ sender: NSMenuItem) {
            guard let code = sender.representedObject as? String else { return }
            selection.wrappedValue = code
        }
    }
}

/// Native text insets also position the placeholder, so the first typed line
/// stays on exactly the same baseline instead of jumping from an overlay.
private struct TranslationEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var wantsKeyboard: Bool
    let placeholder: String
    func makeCoordinator() -> Coordinator { Coordinator(text: $text, wantsKeyboard: $wantsKeyboard) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        let editor = Editor(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 13)
        editor.textColor = .white
        editor.insertionPointColor = .white
        editor.textContainerInset = NSSize(width: 10, height: 8)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel(localized("Source text"))
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.wantsKeyboard = $wantsKeyboard
        guard let editor = scroll.documentView as? Editor else { return }
        editor.placeholder = placeholder
        if editor.string != text {
            editor.string = text
            editor.undoManager?.removeAllActions()
            editor.needsDisplay = true
        }
        // Focus follows an explicit click/selection, never a hover reopen.
        if wantsKeyboard, let window = editor.window, window.firstResponder !== editor {
            window.makeFirstResponder(editor)
        }
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var wantsKeyboard: Binding<Bool>
        init(text: Binding<String>, wantsKeyboard: Binding<Bool>) { self.text = text; self.wantsKeyboard = wantsKeyboard }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? Editor else { return }
            text.wrappedValue = editor.string
            editor.needsDisplay = true
        }
        func textDidBeginEditing(_ notification: Notification) { wantsKeyboard.wrappedValue = true }
    }
    final class Editor: NSTextView {
        var placeholder = "" { didSet { if oldValue != placeholder { needsDisplay = true } } }
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard string.isEmpty else { return }
            let area = NSRect(x: textContainerInset.width, y: textContainerInset.height,
                              width: max(0, bounds.width - 2 * textContainerInset.width), height: bounds.height)
            (placeholder as NSString).draw(in: area, withAttributes: [
                .font: font ?? NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.white.withAlphaComponent(0.58),
            ])
        }
    }
}
