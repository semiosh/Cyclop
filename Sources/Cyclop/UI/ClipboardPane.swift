import SwiftUI
import ImageIO

struct ClipboardPane: View {
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var privacy: PrivacyMode
    @Binding var wantsKeyboard: Bool
    var onTranslate: ((String) -> Void)?
    @State private var query = ""
    @State private var previewID: UUID?
    @FocusState private var focusedItem: UUID?
    private var filtered: [ClipItem] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? clipboard.items : clipboard.items.filter { $0.preview.localizedStandardContains(term) }
    }
    private var preview: ClipItem? {
        clipboard.items.first { $0.id == previewID }
    }
    var body: some View {
        VStack(spacing: 6) {
            if let preview, !privacy.hides(.clipboard, preview.id.uuidString), case .image(let png) = preview.payload {
                ClipboardImagePreview(data: png, clipboard: clipboard, item: preview) { previewID = nil }
            } else {
                toolbar
                if clipboard.isPaused {
                    HStack {
                        Label("History paused", systemImage: "pause.circle")
                        Spacer()
                        Button("Resume history") { clipboard.isPaused = false }.buttonStyle(.plain)
                    }.font(.system(size: 11)).foregroundStyle(Theme.secondary).padding(.horizontal, 8)
                }
                if filtered.isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: "list.clipboard").font(.system(size: 20, weight: .light))
                        Text(query.isEmpty ? localized("Copy text or take a screenshot") : localized("No matches"))
                            .font(.system(size: 13, weight: .medium))
                        if query.isEmpty {
                            Text("⇧⌃⌘4 → Clipboard").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                        }
                    }.foregroundStyle(Theme.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { scroll in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 3) {
                                ForEach(filtered) { item in
                                    ClipRow(item: item, clipboard: clipboard, privacy: privacy,
                                            onPreview: { previewID = item.id; wantsKeyboard = true },
                                            onTranslate: onTranslate, itemFocus: $focusedItem)
                                        .id(item.id)
                                }
                            }
                        }
                        .onChange(of: focusedItem) { _, id in if let id { scroll.scrollTo(id) } }
                    }
                    .onKeyPress(.downArrow) { moveFocus(by: 1); return .handled }
                    .onKeyPress(.upArrow) { moveFocus(by: -1); return .handled }
                }
            }
            footer
        }
        .onChange(of: privacy.covers(.clipboard)) { _, covered in
            if covered { query = ""; previewID = nil }
        }
        .onChange(of: clipboard.items.map(\.id)) { _, ids in
            if let previewID, !ids.contains(previewID) { self.previewID = nil }
        }
        .onKeyPress(.escape) {
            if previewID != nil { previewID = nil; return .handled }
            return .ignored
        }
    }
    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                TextField(localized("Find in clipboard…"), text: $query)
                    .textFieldStyle(.plain)
                    .onTapGesture { wantsKeyboard = true }
                    .onSubmit { if let first = filtered.first { clipboard.copy(first) } }
                    .disabled(privacy.covers(.clipboard))
            }.font(.system(size: 13)).padding(7)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
            PrivacySwitch(privacy: privacy, section: .clipboard)
            Button { clipboard.isPaused.toggle() } label: {
                Image(systemName: clipboard.isPaused ? "play" : "pause")
            }.buttonStyle(NotchButtonStyle(size: 26))
                .help(localized(clipboard.isPaused ? "Resume history" : "Pause history"))
                .accessibilityLabel(localized(clipboard.isPaused ? "Resume history" : "Pause history"))
        }.foregroundStyle(.white)
    }
    private var footer: some View {
        HStack(spacing: 8) {
            Label(localized("Memory only"), systemImage: "shield.lefthalf.filled")
            Text("·")
            Text(clipboard.retention == 0 ? localized("Until quit") : clipboard.retention == 900 ? localized("15 min") : localized("1 hour"))
            Spacer()
            Button("Clear history now") { previewID = nil; clipboard.clear() }
                .buttonStyle(.plain).disabled(clipboard.items.isEmpty)
        }.font(.system(size: 11)).foregroundStyle(Theme.secondary)
            .padding(.top, 7)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
    private func moveFocus(by offset: Int) {
        guard !filtered.isEmpty else { return }
        let index = focusedItem.flatMap { id in filtered.firstIndex { $0.id == id } } ?? (offset > 0 ? -1 : filtered.count)
        focusedItem = filtered[min(max(index + offset, 0), filtered.count - 1)].id
    }
}

private struct ClipRow: View {
    let item: ClipItem
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var privacy: PrivacyMode
    var onPreview: () -> Void
    var onTranslate: ((String) -> Void)?
    var itemFocus: FocusState<UUID?>.Binding
    @State private var hovering = false
    @State private var justCopied = false
    @State private var thumbnail: NSImage?
    @State private var dimensions = ""
    private var isImage: Bool { if case .image = item.payload { return true }; return false }
    private var hidden: Bool { privacy.hides(.clipboard, item.id.uuidString) }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: copy) {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).fill(Theme.surface)
                        if !hidden, let thumbnail {
                            Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit).padding(2)
                        } else {
                            Image(systemName: hidden ? "lock" : item.symbol).font(.system(size: 17)).foregroundStyle(Theme.secondary)
                        }
                    }.frame(width: 60, height: 36).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hidden ? localized("Hidden clipboard item") : item.preview.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 13, weight: .medium)).lineLimit(1)
                        HStack(spacing: 5) {
                            Text(isImage && !dimensions.isEmpty ? dimensions : localized(isImage ? "Image" : "Clipboard"))
                            Text("·")
                            Text(item.date, style: .time).monospacedDigit()
                        }.font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(justCopied ? Color.green : Theme.tertiary).frame(width: 18)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable()
            .focused(itemFocus, equals: item.id)
            .accessibilityLabel(hidden ? localized("Hidden clipboard item") : item.preview)
            .accessibilityHint(localized("Click to copy"))
            .onKeyPress(.space) {
                guard isImage, !hidden else { return .ignored }
                onPreview(); return .handled
            }
            if isImage && !hidden {
                Button(action: onPreview) { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(NotchButtonStyle(size: 26))
                    .help(localized("Preview image · Space"))
                    .accessibilityLabel(localized("Preview image"))
            }
            if privacy.covers(.clipboard) {
                RevealEye(hidden: hidden) { privacy.toggle(item.id.uuidString) }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(hovering ? Theme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copy", action: copy)
            if isImage && !hidden { Button("Preview image", action: onPreview) }
            if !hidden, case .text(let text) = item.payload, let onTranslate {
                Button("Translate text") { onTranslate(text) }
            }
            Divider()
            Button("Remove from history") { clipboard.remove(item) }
        }
        .task(id: hidden) {
            thumbnail = nil; dimensions = ""
            guard !hidden, case .image(let data) = item.payload,
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }
            if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
                dimensions = "\(w) × \(h)"
            }
            if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 160,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ] as CFDictionary) { thumbnail = NSImage(cgImage: image, size: .zero) }
        }
    }
    private func copy() { itemFocus.wrappedValue = item.id; clipboard.copy(item); flash($justCopied) }
}

private struct ClipboardImagePreview: View {
    let data: Data
    @ObservedObject var clipboard: ClipboardStore
    let item: ClipItem
    var close: () -> Void
    @State private var image: NSImage?
    @State private var copied = false
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: close) { Label("Back", systemImage: "chevron.left") }.buttonStyle(.plain)
                Spacer()
                Button { clipboard.copy(item); flash($copied) } label: {
                    Label(copied ? localized("Copied") : localized("Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                }.buttonStyle(.plain)
            }.font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
            } else { Spacer() }
        }
        .task {
            // Display-sized decode: a large screenshot never becomes a full
            // resolution bitmap merely to preview it in this small panel.
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1200,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary) else { return }
            image = NSImage(cgImage: cg, size: .zero)
        }
    }
}
