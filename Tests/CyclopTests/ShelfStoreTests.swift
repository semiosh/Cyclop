import AppKit
import Testing
@testable import Cyclop

@MainActor
struct ShelfStoreTests {
    @Test func removingAndClearingReferencesNeverDeletesFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("first.txt"), second = folder.appendingPathComponent("second.txt")
        try Data("one".utf8).write(to: first)
        try Data("two".utf8).write(to: second)
        let domain = "CyclopTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = ShelfStore(defaults: defaults, pasteboard: MemoryClipboard(), loadsPreviews: false)
        store.add([first, second, first])
        #expect(store.items.count == 2)
        let item = try #require(store.items.first)
        store.remove(item)
        store.clear()
        #expect(try String(contentsOf: first, encoding: .utf8) == "one")
        #expect(try String(contentsOf: second, encoding: .utf8) == "two")
        store.load()
        #expect(store.items.isEmpty)
    }
    @Test func selectionTravelsTogetherAndEvictionDoesNotLeaveGhostSelection() throws {
        let domain = "CyclopTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = ShelfStore(defaults: defaults, pasteboard: MemoryClipboard(), loadsPreviews: false)
        store.add([URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b")])
        let a = store.items[0], b = store.items[1]
        store.select(a, modifiers: [])
        store.select(b, modifiers: .command)
        #expect(Set(store.dragURLs(startingAt: a)) == Set([a.url, b.url]))
        store.add((0..<60).map { URL(fileURLWithPath: "/tmp/cyclop-test-\($0)") })
        #expect(store.items.count == 60)
        #expect(store.selection.isEmpty)
        #expect(store.dragURLs(startingAt: store.items[0]).count == 1)
    }
    @Test func shelfRejectsRemoteURLs() throws {
        let domain = "CyclopTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = ShelfStore(defaults: defaults, pasteboard: MemoryClipboard(), loadsPreviews: false)
        store.add([try #require(URL(string: "https://example.com/file.png"))])
        #expect(store.items.isEmpty)
    }
}
