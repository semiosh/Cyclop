import SwiftUI

/// A local command search; no background service or external index.
struct ToolsPane: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var panel: PanelState
    @State private var query = ""
    @FocusState private var focused: Bool
    private var matches: [NotchViewModel.Tab] {
        (vm.primaryTabs + [.settings]).filter { query.isEmpty || $0.title.localizedStandardContains(query) }
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                TextField(localized("Find tools"), text: $query)
                    .textFieldStyle(.plain).focused($focused)
                    .onSubmit { if let first = matches.first { panel.select(first) } }
                Button { panel.isSearchingTools = false; panel.wantsKeyboard = vm.tab.needsKeyboard } label: {
                    Image(systemName: "xmark")
                }.buttonStyle(.plain).accessibilityLabel(localized("Close search"))
            }
            .font(.system(size: 13)).padding(9)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
            ScrollView(showsIndicators: false) {
              VStack(spacing: 2) {
                ForEach(matches) { tab in
                Button { panel.select(tab) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.symbol).frame(width: 18)
                        Text(tab.title)
                        Spacer()
                        Image(systemName: "return").foregroundStyle(Theme.tertiary)
                    }.font(.system(size: 13)).padding(.horizontal, 10).frame(height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
              }
            }
            if matches.isEmpty { Text("No matches").foregroundStyle(Theme.secondary).font(.system(size: 13)) }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .onAppear { focused = true }
        .onChange(of: panel.wantsKeyboard) { _, wants in focused = wants }
    }
}
