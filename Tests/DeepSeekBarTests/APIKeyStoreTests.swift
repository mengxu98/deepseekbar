import XCTest
@testable import DeepSeekBar

/// In-memory Keychain stand-in so tests never touch the real keychain.
final class InMemoryKeychainStore: KeychainStoring {
    private var items: [String: String] = [:]

    func set(_ key: String, account: String) throws {
        items[account] = key
    }

    func get(account: String) -> String? {
        items[account]
    }

    func delete(account: String) {
        items.removeValue(forKey: account)
    }
}

final class APIKeyStoreTests: XCTestCase {
    private func makeStore() throws -> (APIKeyStore, URL, InMemoryKeychainStore) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepSeekBarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let keychain = InMemoryKeychainStore()
        return (APIKeyStore(baseDirectory: dir, keychain: keychain), dir, keychain)
    }

    func testAddAccountAndLoadStateRoundTrip() throws {
        let (store, dir, keychain) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let account = try store.addAccount(name: "Main", key: "sk-test-1234567890")
        let state = store.loadState()

        XCTAssertEqual(state.accounts.count, 1)
        XCTAssertEqual(state.accounts[0].key, "sk-test-1234567890")
        XCTAssertEqual(keychain.get(account: account.id.uuidString), "sk-test-1234567890")
        XCTAssertEqual(state.activeAccountID, account.id)
    }

    func testDuplicateKeyIsRejected() throws {
        let (store, dir, _) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try store.addAccount(name: "First", key: "sk-duplicate")

        XCTAssertThrowsError(try store.addAccount(name: "Second", key: "sk-duplicate")) { error in
            XCTAssertEqual(error as? APIKeyStoreError, .duplicateKey)
        }
        // Whitespace variants count as the same key.
        XCTAssertThrowsError(try store.addAccount(name: "Third", key: "  sk-duplicate  "))
        XCTAssertEqual(store.loadState().accounts.count, 1)
    }

    func testEmptyKeyIsRejected() throws {
        let (store, dir, _) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertThrowsError(try store.addAccount(name: "X", key: "   ")) { error in
            XCTAssertEqual(error as? APIKeyStoreError, .emptyKey)
        }
    }

    func testRenameAccount() throws {
        let (store, dir, _) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let account = try store.addAccount(name: "Old", key: "sk-rename-me")
        try store.updateAccount(id: account.id, name: "New")

        XCTAssertEqual(store.loadState().accounts[0].displayName, "New")
    }

    func testRemoveAccountCleansKeychain() throws {
        let (store, dir, keychain) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let account = try store.addAccount(name: "Doomed", key: "sk-gone")
        try store.removeAccount(id: account.id)

        XCTAssertNil(keychain.get(account: account.id.uuidString))
        XCTAssertTrue(store.loadState().accounts.isEmpty)
    }

    func testLegacyPlaintextMigration() throws {
        let (store, dir, keychain) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        struct LegacyWritable: Codable {
            struct Account: Codable {
                let id: UUID
                let name: String
                let key: String
                let createdAt: Date
            }
            let accounts: [Account]
        }

        let id = UUID()
        let legacy = LegacyWritable(accounts: [
            .init(id: id, name: "Old", key: "sk-plaintext", createdAt: Date())
        ])
        try JSONEncoder().encode(legacy).write(to: dir.appendingPathComponent("api_keys.json"))

        let state = store.loadState()

        XCTAssertEqual(state.accounts[0].key, "sk-plaintext", "key restored from keychain after migration")
        XCTAssertEqual(keychain.get(account: id.uuidString), "sk-plaintext")

        let onDisk = try String(contentsOf: dir.appendingPathComponent("api_keys.json"), encoding: .utf8)
        XCTAssertFalse(onDisk.contains("sk-plaintext"), "plaintext key must be scrubbed from disk")
    }

    func testLegacyMigrationPreservesExistingKeychainAccounts() throws {
        let (store, dir, keychain) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let existing = try store.addAccount(name: "Existing", key: "sk-existing")
        let legacyID = UUID()
        let legacyJSON = """
        {"accounts":[
          {"id":"\(existing.id.uuidString)","name":"Existing","createdAt":0},
          {"id":"\(legacyID.uuidString)","name":"Legacy","key":"sk-legacy","createdAt":0}
        ],"activeAccountID":"\(existing.id.uuidString)"}
        """
        try Data(legacyJSON.utf8).write(to: dir.appendingPathComponent("api_keys.json"))

        let state = store.loadState()

        XCTAssertEqual(state.accounts.map(\.key), ["sk-existing", "sk-legacy"])
        XCTAssertEqual(keychain.get(account: existing.id.uuidString), "sk-existing")
    }

    func testKeysNeverWrittenToDisk() throws {
        let (store, dir, _) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try store.addAccount(name: "Secret", key: "sk-super-secret-value")

        let onDisk = try String(contentsOf: dir.appendingPathComponent("api_keys.json"), encoding: .utf8)
        XCTAssertFalse(onDisk.contains("sk-super-secret-value"))
    }
}
