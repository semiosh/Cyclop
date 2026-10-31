import AppKit

/// One screen's share of the panel: whether the notch on *this* display is
/// open, and the geometry it is cut from.
///
/// The split is the pointer's. It is on exactly one display at a time, so
/// everything it drives — open, drop-targeted, holding the keyboard — belongs
/// to a screen, while the tab, the stores and the running services are the
/// same everywhere and stay in `NotchViewModel`.
@MainActor
final class PanelState: ObservableObject {
    @Published var isOpen = false { didSet { notify(isOpen != oldValue) } }
    @Published var isDropTargeted = false { didSet { notify(isDropTargeted != oldValue) } }
    /// Whether this screen's panel holds the keyboard. Per screen because only
    /// one window can be key, and it is this one the user clicked into.
    @Published var wantsKeyboard = false { didSet { notify(wantsKeyboard != oldValue) } }

    var isMenuTracking = false
    @Published var isDraggingOut = false
    @Published var isSearchingTools = false

    let geometry: NotchGeometry
    private let vm: NotchViewModel

    /// Raised when any of the three above moves, so whoever owns every screen
    /// can recompute what the shared model needs to know about the panels.
    var onChange: (() -> Void)?

    init(geometry: NotchGeometry, vm: NotchViewModel) {
        self.geometry = geometry
        self.vm = vm
    }

    /// Whether this screen is showing anything beyond the bare notch.
    var isActive: Bool { isOpen || isDropTargeted }

    /// The expanded settings pane has more height; other tools stay compact.
    var openBodySize: CGSize {
        vm.tab.wantsTallBody ? geometry.tallExpandedSize : geometry.expandedSize
    }

    /// Size of the visible body for the current state.
    var bodySize: CGSize { isActive ? openBodySize : geometry.collapsedSize }

    /// Only an explicit selection requests the keyboard; hovering never does.
    func select(_ tab: NotchViewModel.Tab) {
        isSearchingTools = false
        vm.tab = tab
        wantsKeyboard = tab.needsKeyboard
    }

    private func notify(_ changed: Bool) {
        guard changed else { return }
        onChange?()
    }
}
