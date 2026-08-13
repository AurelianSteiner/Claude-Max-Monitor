//
//  TeamFolderAccess.swift
//  Usage4Claude
//
//  Team-Übersicht — Teil 3: der geteilte Ordner.
//
//  Die App läuft in der Sandbox. Ein Ordner in iCloud Drive, Dropbox oder
//  Google Drive liegt außerhalb des Containers, also gilt:
//
//    1. Der Nutzer wählt den Ordner selbst über einen Öffnen-Dialog aus
//       (`com.apple.security.files.user-selected.read-write`).
//    2. Gemerkt wird er als Sicherheits-Lesezeichen — `Data`, kein Pfad
//       (`com.apple.security.files.bookmarks.app-scope`). Ein Pfad-String
//       wäre nach dem nächsten Start wertlos.
//    3. Jeder Zugriff läuft zwischen `startAccessingSecurityScopedResource()`
//       und `stopAccessingSecurityScopedResource()`.
//
//  Punkt 3 ist der heikle: Ein `start` ohne `stop` leckt eine Sandbox-
//  Ressource, und das fällt erst auf, wenn irgendwann gar kein Zugriff mehr
//  klappt. Deshalb gibt es hier genau **eine** Stelle, die `start` aufruft
//  (`beginAccess()`), und sie liefert ein Objekt zurück, dessen `end()` per
//  `defer` in `withFolder(_:)` garantiert läuft — auch wenn der Block wirft.
//  Außerhalb von `withFolder(_:)` gibt es keinen Zugriff auf den Ordner.
//
//  Copyright © 2025 f-is-h. All rights reserved.
//

import AppKit
import Combine
import OSLog

final class TeamFolderAccess: ObservableObject {

    /// Gemeinsame Instanz — Einstellungen und Übersicht greifen auf denselben Ordner zu
    static let shared = TeamFolderAccess()

    // MARK: - Anzeige (nur Hauptthread schreiben)

    /// Name des gewählten Ordners, z. B. „Claude-Team"
    @Published private(set) var folderName: String?
    /// Pfad für Tooltips, mit „~" abgekürzt
    @Published private(set) var folderPath: String?
    /// Ordner ist eingerichtet, lässt sich aber gerade nicht erreichen
    /// (Volume nicht eingehängt, Ordner gelöscht, Rechte weg)
    @Published private(set) var isUnreachable = false

    // MARK: - Zustand

    private let defaults = UserDefaults.standard
    /// Lesezeichen-Daten. Wird auch aus Hintergrund-Queues gelesen, darum
    /// hinter einem Lock statt als `@Published`.
    private var bookmark: Data?
    private let lock = NSLock()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        bookmark = defaults.data(forKey: TeamDefaultsKeys.folderBookmark)

        // Das Auflösen eines Lesezeichens kann hängen, wenn das Volume erst
        // eingehängt werden muss — also nie beim Start auf dem Hauptthread.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.updateDisplayInfo()
        }

        // Ohne Team ergibt der Ordner keinen Sinn mehr.
        NotificationCenter.default.publisher(for: .teamConfigChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard TeamStore.shared.hasTeam == false else { return }
                self?.clearFolder()
            }
            .store(in: &cancellables)
    }

    // MARK: - Abfragen

    /// Ist ein Ordner hinterlegt?
    var hasFolder: Bool {
        lock.lock()
        defer { lock.unlock() }
        return bookmark != nil
    }

    // MARK: - Ordner wählen

    /// Öffnet den Auswahldialog. **Nur vom Hauptthread aufrufen.**
    /// - Returns: `true`, wenn ein Ordner gewählt und gemerkt wurde.
    @discardableResult
    func chooseFolder() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = L.Team.folderChooseMessage
        panel.prompt = L.Team.folderChoosePrompt

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return adopt(url)
    }

    /// Merkt sich einen Ordner (aus dem Dialog oder per Drag & Drop).
    @discardableResult
    func adopt(_ url: URL) -> Bool {
        guard let data = makeBookmark(for: url) else {
            Logger.team.error("Lesezeichen für den Team-Ordner konnte nicht erstellt werden")
            return false
        }
        store(bookmark: data)
        Logger.team.notice("Team-Ordner gewählt")
        return true
    }

    /// Vergisst den Ordner. Im Ordner selbst wird nichts verändert.
    func clearFolder() {
        lock.lock()
        let hadFolder = bookmark != nil
        bookmark = nil
        lock.unlock()

        guard hadFolder else { return }
        defaults.removeObject(forKey: TeamDefaultsKeys.folderBookmark)
        publish(name: nil, path: nil, unreachable: false)
        NotificationCenter.default.post(name: .teamFolderChanged, object: nil)
        Logger.team.notice("Team-Ordner entfernt")
    }

    /// Zeigt den Ordner im Finder.
    func revealInFinder() {
        withFolder { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    // MARK: - Zugriff

    /// Führt `body` mit dem geteilten Ordner aus — innerhalb des
    /// Sicherheits-Scopes, der danach **immer** wieder geschlossen wird.
    ///
    /// - Returns: Das Ergebnis von `body`, oder `nil`, wenn kein Ordner
    ///   hinterlegt ist oder der Zugriff nicht klappt. Es gibt keinen anderen
    ///   Weg an den Ordner: So bleibt `start`/`stop` an genau einer Stelle
    ///   ausbalanciert.
    /// - Note: Von jedem Thread aufrufbar.
    func withFolder<T>(_ body: (URL) throws -> T) rethrows -> T? {
        guard let access = beginAccess() else { return nil }
        defer { access.end() }
        return try body(access.url)
    }

    // MARK: - Intern

    /// Ein offener Sicherheits-Scope. `end()` schließt ihn — und zwar nur
    /// dann, wenn `start…` vorher wirklich `true` geliefert hat.
    private struct ScopedFolder {
        let url: URL
        let didStart: Bool

        func end() {
            guard didStart else { return }
            url.stopAccessingSecurityScopedResource()
        }
    }

    /// Löst das Lesezeichen auf und öffnet den Sicherheits-Scope.
    /// Einzige Stelle im Projekt, die `startAccessingSecurityScopedResource()`
    /// aufruft — jede Rückgabe ungleich `nil` muss mit `end()` gepaart werden.
    private func beginAccess() -> ScopedFolder? {
        lock.lock()
        let data = bookmark
        lock.unlock()

        guard let data else { return nil }

        var isStale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: data,
                          options: [.withSecurityScope],
                          relativeTo: nil,
                          bookmarkDataIsStale: &isStale)
        } catch {
            Logger.team.error("Team-Ordner nicht auflösbar: \(error.localizedDescription, privacy: .public)")
            markUnreachable(true)
            return nil
        }

        guard url.startAccessingSecurityScopedResource() else {
            Logger.team.error("Zugriff auf den Team-Ordner verweigert")
            markUnreachable(true)
            return nil
        }

        // Ab hier ist der Scope offen: Jeder Rückgabepfad muss über `end()`.
        let scoped = ScopedFolder(url: url, didStart: true)

        if isStale {
            // Ordner verschoben oder umbenannt: Solange der Scope offen ist,
            // lässt sich ein frisches Lesezeichen ziehen. Klappt das nicht,
            // bleibt das alte — es funktioniert ja gerade noch.
            if let refreshed = makeBookmark(for: url) {
                store(bookmark: refreshed, notify: false)
                Logger.team.notice("Lesezeichen des Team-Ordners erneuert")
            } else {
                Logger.team.error("Veraltetes Lesezeichen ließ sich nicht erneuern")
            }
        }

        markUnreachable(false)
        return scoped
    }

    private func makeBookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(options: [.withSecurityScope],
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        } catch {
            Logger.team.error("bookmarkData fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func store(bookmark data: Data, notify: Bool = true) {
        lock.lock()
        bookmark = data
        lock.unlock()

        defaults.set(data, forKey: TeamDefaultsKeys.folderBookmark)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.updateDisplayInfo()
        }
        if notify {
            NotificationCenter.default.post(name: .teamFolderChanged, object: nil)
        }
    }

    /// Liest Name und Pfad des Ordners neu ein. Läuft im Hintergrund.
    private func updateDisplayInfo() {
        guard hasFolder else {
            publish(name: nil, path: nil, unreachable: false)
            return
        }

        let info: (name: String, path: String)? = withFolder { url in
            (url.lastPathComponent, (url.path as NSString).abbreviatingWithTildeInPath)
        }

        if let info {
            publish(name: info.name, path: info.path, unreachable: false)
        } else {
            // Lesezeichen ist da, der Ordner gerade nicht erreichbar.
            publish(name: nil, path: nil, unreachable: true)
        }
    }

    private func markUnreachable(_ value: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isUnreachable != value else { return }
            self.isUnreachable = value
        }
    }

    private func publish(name: String?, path: String?, unreachable: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.folderName = name
            self.folderPath = path
            self.isUnreachable = unreachable
        }
    }
}
