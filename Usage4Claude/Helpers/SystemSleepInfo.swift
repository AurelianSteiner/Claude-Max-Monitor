//
//  SystemSleepInfo.swift
//  Usage4Claude
//
//  Liest die AKTUELLEN Schlaf-Einstellungen des Systems — `pmset -g` einmal
//  ausführen und zwei Zeilen herausfischen:
//
//    • `SleepDisabled 1` → der Mac schläft nie (sudo pmset disablesleep 1),
//      die beiden Wach-Schalter im Kopf der Übersicht ändern daran nichts.
//    • `displaysleep 0` → der Bildschirm geht nie von selbst aus.
//
//  Wozu: Auf einem so eingestellten Mac sind die Schalter wirkungslos — die
//  Oberfläche sagt das dann dazu (Tooltip, Markierung, Live-Werte in den
//  Einstellungen), statt so zu tun, als schaltete sie etwas.
//
//  Verhalten im Fehlerfall: `pmset` nicht startbar (Sandbox), Ausgabe nicht
//  lesbar, Zeile fehlt → die Werte bleiben `nil` und die Oberfläche zeigt
//  schlicht nichts Zusätzliches an. Kein Absturz, kein Dialog.
//
//  Thread-Regel: `refresh()` vom Hauptthread; das Ausführen läuft auf einer
//  Utility-Queue (Process.run + Pipe können blockieren), veröffentlicht wird
//  auf dem Hauptthread. Höchstens einmal pro Minute wird wirklich gelesen.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import Combine
import OSLog

final class SystemSleepInfo: ObservableObject {

    /// Gemeinsame Instanz — Übersichtskopf und Einstellungen lesen dieselben Werte
    static let shared = SystemSleepInfo()

    // MARK: - Veröffentlichter Zustand (nur Hauptthread)

    /// `true` = `SleepDisabled 1`, der Mac schläft nie. `nil` = nicht lesbar.
    @Published private(set) var sleepDisabled: Bool?
    /// Minuten bis zum Bildschirm-Aus laut `displaysleep`; 0 = nie.
    /// `nil` = nicht lesbar.
    @Published private(set) var displaySleepMinutes: Int?

    // MARK: - Intern

    /// Mindestabstand zweier echter Lesevorgänge
    private static let minimumGap: TimeInterval = 60

    private let queue = DispatchQueue(label: "xyz.fi5h.Usage4Claude.system-sleep-info", qos: .utility)
    private var lastReadAt: Date?
    private var isReading = false

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "xyz.fi5h.Usage4Claude",
        category: "SystemSleepInfo"
    )

    private init() {}

    // MARK: - Lesen

    /// Liest die Werte neu — gedacht für `onAppear` der Übersicht und der
    /// Einstellungen. Drosselt sich selbst auf einen Lauf pro Minute.
    /// **Nur vom Hauptthread aufrufen.**
    func refresh() {
        dispatchPrecondition(condition: .onQueue(.main))

        guard !isReading else { return }
        if let last = lastReadAt, Date().timeIntervalSince(last) < Self.minimumGap { return }

        isReading = true
        queue.async { [weak self] in
            let output = Self.runPMSet()
            let parsed = output.map(Self.parse) ?? (sleepDisabled: nil, displaySleepMinutes: nil)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isReading = false
                self.lastReadAt = Date()
                if self.sleepDisabled != parsed.sleepDisabled {
                    self.sleepDisabled = parsed.sleepDisabled
                }
                if self.displaySleepMinutes != parsed.displaySleepMinutes {
                    self.displaySleepMinutes = parsed.displaySleepMinutes
                }
            }
        }
    }

    /// Führt `/usr/bin/pmset -g` aus. `nil`, wenn der Start scheitert (etwa
    /// weil die Sandbox das Ausführen verbietet) oder nichts zurückkommt.
    private static func runPMSet() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()   // Fehlermeldungen stumm schlucken

        do {
            try process.run()
        } catch {
            log.notice("pmset ließ sich nicht ausführen: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        // Erst die Pipe leer lesen, dann auf das Ende warten — andersherum
        // könnte ein voller Puffer beide Seiten festhalten. `pmset -g` liefert
        // ein paar Dutzend Zeilen und endet sofort.
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0, !data.isEmpty else {
            log.notice("pmset lieferte keine lesbare Ausgabe")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Fischt `SleepDisabled` und `displaysleep` aus der `pmset -g`-Ausgabe.
    /// Zeilen sehen so aus (Einrückung und Spaltenbreite schwanken):
    ///
    ///      SleepDisabled          1
    ///      displaysleep           0
    ///
    /// Fehlt eine Zeile oder ist der Wert keine Zahl, bleibt der jeweilige
    /// Wert `nil`.
    static func parse(_ output: String) -> (sleepDisabled: Bool?, displaySleepMinutes: Int?) {
        var sleepDisabled: Bool?
        var displaySleep: Int?

        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2, let value = Int(parts[1]) else { continue }

            switch parts[0] {
            case "SleepDisabled": sleepDisabled = value != 0
            case "displaysleep":  displaySleep = value
            default: break
            }
        }
        return (sleepDisabled, displaySleep)
    }
}
