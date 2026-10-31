import SwiftUI

struct NotchContentView: View {
    @ObservedObject var vm: NotchViewModel
    /// This screen's share of the panel. Everything the pointer decides is
    /// here; everything shown is in `vm`, the same on every display.
    @ObservedObject var panel: PanelState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOpen: Bool { panel.isActive }
    private var size: CGSize { panel.bodySize }
    private var topRadius: CGFloat { isOpen ? Theme.openTopRadius : Theme.collapsedTopRadius }

    /// Whether the shape is painted at all.
    ///
    /// Folded over a real notch there is nothing to paint: the notch is a hole,
    /// and a hole is already black. The filled shape on top of it is invisible
    /// — but only for as long as what is behind it stays black, and that is not
    /// something the panel gets to assume. The window is `.stationary` and
    /// joins every space, so it stands still while the desktop moves: in
    /// Mission Control and mid-swipe between spaces the desktop shrinks away
    /// and the "notch" is left hanging in the air as a black rectangle over the
    /// Spaces bar. It reads as a second, squarer notch, which is exactly what
    /// it is — a picture of a hole with no hole behind it.
    ///
    /// A drawn notch is the opposite case: there the shape *is* the notch, and
    /// it has to be visible wherever the panel stands. So the rule is narrow —
    /// only the display that has a real cutout, and only while the panel has
    /// nothing of its own to show.
    ///
    /// "Nothing of its own" is asked of the body rather than of `isOpen`, and
    /// the difference is not stylistic. On a hole the body is the notch exactly
    /// when there is nothing to show — folded, `bodySize` is `collapsedSize`,
    /// and on a hole that is the notch itself —
    /// so any future state that grows the folded strip paints itself without
    /// anyone remembering to come back here. Keyed on `isOpen`, the next such
    /// state would draw its text onto a transparent background: white letters
    /// standing on the desktop with nothing behind them.
    private var paintsShape: Bool {
        !panel.geometry.isPhysical || size != panel.geometry.notchSize
    }

    var body: some View {
        // The shape is wider than the body by `topRadius` on each side: that
        // slack is where the concave shoulders live, so it must not be clipped.
        ZStack(alignment: .top) {
            NotchShape(
                topRadius: topRadius,
                bottomRadius: isOpen ? Theme.openBottomRadius : Theme.collapsedBottomRadius
            )
            .fill(paintsShape ? Color.black : Color.clear)
            .frame(width: size.width + 2 * topRadius, height: size.height)
            .shadow(color: .black.opacity(isOpen ? 0.32 : 0), radius: 12, y: 5)

            VStack(spacing: 0) {
                header
                if isOpen {
                    content
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipped()
        }
        .frame(width: size.width + 2 * topRadius, height: size.height, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Theme.openAnimation, value: isOpen)
        .animation(Theme.paneAnimation, value: vm.tab)
    }

    // MARK: - Header
    //
    // This strip sits directly on top of the menu bar. Menu bar utilities such
    // as Ice watch for clicks there with a global event monitor — a passive
    // observer that sees the click no matter which window consumes it — so
    // clicking here toggles them as a side effect. Nothing interactive goes in
    // this row; the tab switcher lives in the rail below.

    private var header: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Color.clear.frame(width: panel.geometry.notchSize.width, height: 1)
            Spacer(minLength: 0)
            if isOpen {
                trailing
                    .padding(.trailing, 16)
                    .transition(.opacity)
            }
        }
        .frame(height: panel.geometry.notchSize.height)
    }

    @ViewBuilder
    private var trailing: some View {
        switch vm.tab {
        case .media:
            HStack(spacing: 6) {
                if vm.media.track != nil {
                    EqualizerBars(isAnimating: vm.media.isPlaying)
                }
                Text(vm.media.sourceName ?? "")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
            }
        case .shelf:
            counter(vm.shelf.items.count)
        case .clipboard:
            counter(vm.clipboard.items.count)
        case .translate:
            // Nothing: the columns name both languages already, and the strip
            // is the one part of the panel worth not spending on a repeat.
            EmptyView()
        case .settings:
            EmptyView()
        }
    }

    @ViewBuilder
    private func counter(_ value: Int) -> some View {
        if value > 0 {
            Text("\(value)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
        }
    }

    // MARK: - Body

    private var content: some View {
        VStack(spacing: 6) {
            ToolNavigation(vm: vm, panel: panel)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ZStack {
                if panel.isSearchingTools {
                    ToolsPane(vm: vm, panel: panel)
                } else {
                    pane.id(vm.tab).transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, NotchGeometry.bodyBottomPadding)
    }

    @ViewBuilder
    private var pane: some View {
        switch vm.tab {
        case .media:
            MediaPane(media: vm.media)
        case .shelf:
            ShelfPane(shelf: vm.shelf, isTargeted: panel.isDropTargeted,
                      onDragChanged: { panel.isDraggingOut = $0 })
        case .clipboard:
            ClipboardPane(clipboard: vm.clipboard, privacy: vm.privacy,
                          wantsKeyboard: $panel.wantsKeyboard,
                          onTranslate: vm.isVisible(.translate) ? { text in
                              vm.translate(text)
                              panel.wantsKeyboard = true
                          } : nil)
        case .translate:
            TranslatePane(translator: vm.translator, wantsKeyboard: $panel.wantsKeyboard)
        case .settings:
            SettingsPane(vm: vm, shelf: vm.shelf, screenshots: vm.screenshotFolder)
        }
    }
}

private struct ToolNavigation: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var panel: PanelState
    @State private var hovered: NotchViewModel.Tab?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(vm.primaryTabs) { tab in
                Button { panel.select(tab) } label: {
                    Text(tab.title)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(vm.tab == tab && !panel.isSearchingTools ? Theme.surfaceHover : hovered == tab ? Theme.surface : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(vm.tab == tab ? Color.white : Theme.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(vm.tab == tab ? .isSelected : [])
                .onHover { hovered = $0 ? tab : nil }
            }
            Spacer(minLength: 0)
            Button {
                panel.isSearchingTools.toggle()
                panel.wantsKeyboard = panel.isSearchingTools
            } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(NotchButtonStyle(size: 26))
                .help(localized("Find tools · ⌘K"))
                .accessibilityLabel(localized("Find tools"))
            Button { panel.select(.settings) } label: { Image(systemName: "gearshape") }
                .buttonStyle(NotchButtonStyle(size: 26))
                .help(localized("Settings"))
                .accessibilityLabel(localized("Settings"))
        }
        .padding(.top, 3)
    }
}
