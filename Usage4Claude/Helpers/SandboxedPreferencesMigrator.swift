//
//  SandboxedPreferencesMigrator.swift
//  Usage4Claude
//
//  Einmaliger Import der alten Sandbox-Einstellungen.
//
//  Bis 1.x lief die App in der App Sandbox; ihre UserDefaults lagen deshalb im
//  Container:
//
//      ~/Library/Containers/xyz.fi5h.Usage4Claude/Data/Library/Preferences/
//          xyz.fi5h.Usage4Claude.plist
//
//  Ohne Sandbox (ab 2.0) liest UserDefaults dagegen ~/Library/Preferences —
//  beim ersten Start sähe ALLES leer aus: Menüleisten-Modus, Refresh, Sprache,
//  Wach-Schalter, Team-Server-Konfiguration. (Die Konten selbst liegen im
//  Schlüsselbund und überleben den Umzug ohnehin.)
//
//  Deshalb importiert `run()` die Container-Werte genau einmal — und zwar als
//  ALLERERSTE Anweisung des Prozesses (siehe `AppMain.main()`), bevor irgendein
//  Code UserDefaults anfasst (Sparkle, UserSettings.shared, SleepGuard …).
//
//  Regeln:
//    • Nur Schlüssel übernehmen, die im Standard-Bereich noch NICHT existieren —
//      wer 2.0 schon benutzt hat, behält seine neuen Werte.
//    • Schlüssel wortwörtlich kopieren, nichts umbenennen. Das gilt auch für die
//      DEBUG_-Präfix-Konvention der Debug-Builds: präfixierte wie unpräfixierte
//      Schlüssel wandern unverändert mit.
//    • Der Container wird NICHT gelöscht — wer auf 1.x zurückgeht, findet alles
//      unverändert vor.
//    • Ein kaputtes Plist darf den Start nicht reißen: loggen, Marker setzen,
//      weiter. AUSNAHME fehlende Lese-Erlaubnis (Container-Schutz seit
//      Sonoma): dann bleibt der Marker weg und der nächste Start versucht es
//      erneut — ein einmalig verweigerter Zugriff darf die Einstellungen
//      nicht für immer verwerfen.
//
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import OSLog

enum SandboxedPreferencesMigrator {

    /// Marker im Standard-Bereich: Import ist gelaufen (oder wurde wegen eines
    /// kaputten Plists bewusst übersprungen) — nie wieder versuchen.
    static let markerKey = "didImportSandboxedPreferences"

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "xyz.fi5h.Usage4Claude",
        category: "SandboxedPreferencesMigrator"
    )

    /// Muss vor JEDEM anderen UserDefaults-Zugriff laufen — `AppMain.main()`
    /// ruft sie als allererste Anweisung auf.
    static func run() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: markerKey) == nil else { return }

        let bundleID = Bundle.main.bundleIdentifier ?? "xyz.fi5h.Usage4Claude"
        let containerPlist = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Preferences/\(bundleID).plist")

        // Kein Container = Neuinstallation oder längst migriert und aufgeräumt —
        // nichts zu übernehmen. Der Marker bleibt bewusst ungesetzt: taucht der
        // Container später doch auf (Downgrade/Upgrade-Pingpong), greift der
        // Import beim nächsten Start. Die Prüfung kostet nur einen stat().
        guard FileManager.default.fileExists(atPath: containerPlist.path) else { return }

        do {
            let data = try Data(contentsOf: containerPlist)
            guard let entries = try PropertyListSerialization
                .propertyList(from: data, options: [], format: nil) as? [String: Any]
            else {
                throw CocoaError(.propertyListReadCorrupt)
            }

            var imported = 0
            for (key, value) in entries where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
                imported += 1
            }
            defaults.set(true, forKey: markerKey)
            log.notice("Sandbox-Einstellungen importiert: \(imported) von \(entries.count) Schlüsseln übernommen")
        } catch {
            // Zwei sehr verschiedene Fehlerbilder:
            //
            // • KEINE LESE-ERLAUBNIS (NSFileReadNoPermissionError): Seit
            //   Sonoma schützt macOS App-Container — der allererste Zugriff
            //   kann an einer (abgelehnten) Systemnachfrage oder MDM-Policy
            //   scheitern. Das ist kein kaputtes Plist, sondern ein „jetzt
            //   gerade nicht“: Marker NICHT setzen, nächster Start versucht
            //   es still erneut. Sonst wären die Einstellungen wegen eines
            //   einzigen verweigerten Zugriffs für immer verloren.
            //
            // • Alles andere (Plist wirklich kaputt/unlesbar): nicht crashen,
            //   Marker setzen, nie erneut versuchen.
            if let cocoaError = error as? CocoaError, cocoaError.code == .fileReadNoPermission {
                log.error("Kein Lesezugriff auf den alten Container — Import wird beim nächsten Start erneut versucht: \(error.localizedDescription, privacy: .public)")
                return
            }
            defaults.set(true, forKey: markerKey)
            log.error("Sandbox-Einstellungen nicht lesbar, Import übersprungen: \(error.localizedDescription, privacy: .public)")
        }
    }
}
