import XCTest
import UIKit
@testable import Duet

final class NativeStoreTests: XCTestCase {
    @MainActor private func store() throws -> NativeStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DuetTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return NativeStore(directory: directory, testMode: true)
    }
    @MainActor func testFontImportDuplicateAndRemoval() throws {
        let store = try store()
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cormorant", withExtension: "ttf"))
        try store.importFont(source)
        let first = try XCTUnwrap(store.data.preferences.fonts.first)
        XCTAssertNotNil(UIFont(name: first.postScriptName, size: 16))
        XCTAssertEqual(store.data.preferences.typography, "custom")
        try store.importFont(source)
        XCTAssertEqual(store.data.preferences.fonts.count, 1)
        store.removeFont(first)
        XCTAssertEqual(store.data.preferences.typography, "native")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(first.path).path))
        let invalid = store.url("invalid.ttf")
        try Data("invalid font".utf8).write(to: invalid)
        XCTAssertThrowsError(try store.importFont(invalid))
        XCTAssertTrue(store.data.preferences.fonts.isEmpty)
    }
    @MainActor func testClearKeepsOtherChannelMemoryAndDraftAssets() throws {
        let store = try store()
        let attachment = ChatAttachment(name: "photo", path: "photo.jpg", photo: true, bytes: 4)
        try Data([1, 2, 3, 4]).write(to: store.url(attachment.path))
        let message = ChatMessage(author: "me", text: "old", attachments: [attachment])
        store.data.messages = ["gpt": [message], "claude": [ChatMessage(author: "claude", text: "keep")]]
        store.data.personas["gpt"]?.memories = [Memory(text: "keep memory", thread: "gpt", message: message.id)]
        store.data.drafts["gpt"] = "unfinished"
        store.setDraftAttachments([attachment], thread: "gpt")
        store.removeChatHistory(["gpt"])
        XCTAssertTrue(store.data.messages["gpt"]!.isEmpty)
        XCTAssertEqual(store.data.messages["claude"]?.count, 1)
        XCTAssertEqual(store.data.personas["gpt"]?.memories.first?.text, "keep memory")
        XCTAssertNil(store.data.personas["gpt"]?.memories.first?.message)
        XCTAssertEqual(store.data.drafts["gpt"], "unfinished")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(attachment.path).path))
        store.setDraftAttachments([], thread: "gpt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(attachment.path).path))
    }
    @MainActor func testPhotoDownsamplingAndPersistentPreferences() throws {
        let store = try store()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2200)).image { ctx in UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 3000, height: 2200)) }
        let attachment = try store.savePhoto(try XCTUnwrap(image.pngData()))
        let resized = try XCTUnwrap(store.image(attachment.path))
        XCTAssertLessThanOrEqual(max(resized.size.width, resized.size.height), 1600)
        XCTAssertLessThanOrEqual(attachment.bytes, 2 * 1024 * 1024)
        XCTAssertThrowsError(try store.savePhoto(Data("bad".utf8)))
        store.data.preferences.typography = "artistic"
        store.data.personas["gpt"]?.userCallName = "私聊称呼"
        store.data.personas["gpt"]?.groupCallName = "群聊称呼"
        store.data.routes = ["gpt:gpt": ModelSelection(source: "codex", model: "test-model")]
        store.persist()
        let reopened = NativeStore(directory: store.directory, testMode: true)
        XCTAssertEqual(reopened.data.preferences.typography, "native")
        XCTAssertEqual(reopened.data.personas["gpt"]?.groupCallName, "群聊称呼")
        XCTAssertEqual(reopened.selection(thread: "gpt").source, "codex")
        XCTAssertEqual(reopened.selection(thread: "group").source, "chatgpt-web")
    }
}
