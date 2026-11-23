//
//  DesktopEntryTests.swift
//  CacaoShellKitTests
//

import Foundation
import Testing
@testable import CacaoShellKit

@Suite struct DesktopEntryTests {

    let contents = """
        [Desktop Entry]
        Type=Application
        Name=Text Editor
        Name[es]=Editor de texto
        Comment=Edit text files
        Icon=accessories-text-editor
        Exec="/usr/bin/text editor" --new-window %F
        StartupWMClass=org.example.TextEditor
        Categories=Utility;TextEditor;

        [Desktop Action new-window]
        Name=New Window
        Exec=text-editor --new-window
        """

    @Test func parsesMainGroup() throws {
        let entry = try #require(DesktopEntry(id: "org.example.TextEditor", contents: contents))
        #expect(entry.name == "Text Editor")
        #expect(entry.comment == "Edit text files")
        #expect(entry.icon == "accessories-text-editor")
        #expect(entry.categories == ["Utility", "TextEditor"])
        #expect(entry.noDisplay == false)
    }

    @Test func commandLineDropsFieldCodes() throws {
        let entry = try #require(DesktopEntry(id: "org.example.TextEditor", contents: contents))
        #expect(entry.commandLine == ["/usr/bin/text editor", "--new-window"])
    }

    @Test func matchesAppID() throws {
        let entry = try #require(DesktopEntry(id: "org.example.TextEditor", contents: contents))
        #expect(entry.matches(appID: "org.example.TextEditor"))
        #expect(entry.matches(appID: "TextEditor"))
        #expect(!entry.matches(appID: "org.example.Other"))
    }

    @Test func rejectsNonApplications() {
        #expect(DesktopEntry(id: "link", contents: "[Desktop Entry]\nType=Link\nName=Home\n") == nil)
    }

    @Test func earlierDirectoryWins() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let user = root.appendingPathComponent("user")
        let system = root.appendingPathComponent("system")
        try fileManager.createDirectory(at: user, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: system.appendingPathComponent("vendor"), withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        try "[Desktop Entry]\nType=Application\nName=Mine\n".write(to: user.appendingPathComponent("app.desktop"), atomically: true, encoding: .utf8)
        try "[Desktop Entry]\nType=Application\nName=System\n".write(to: system.appendingPathComponent("app.desktop"), atomically: true, encoding: .utf8)
        try "[Desktop Entry]\nType=Application\nName=Nested\n".write(to: system.appendingPathComponent("vendor/tool.desktop"), atomically: true, encoding: .utf8)

        let entries = DesktopEntry.installed(in: [user, system])
        #expect(entries.map(\.id) == ["app", "vendor-tool"])
        #expect(entries.first?.name == "Mine")
    }
}
