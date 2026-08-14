//
//  PrivilegedPower.swift
//  Usage4Claude
//
//  Der privilegierte Teil von „Bleib wach“: `pmset -a disablesleep 1/0` —
//  die einzige Einstellung, die den Mac auch ZUGEKLAPPT wach hält. Sie
//  verlangt root; IOKit-Assertions (SleepGuard) reichen dafür nicht.
//
//  Einmal-Freigabe statt Dauergefrage:
//
//    1. Erst der stille Versuch: `sudo -n /usr/bin/pmset -a disablesleep …`.
//       Er gelingt nur, wenn die Einmal-Regel schon installiert ist.
//    2. Schlägt er fehl (und ist ein interaktiver Aufruf erlaubt), zeigt
//       macOS über osascript („do shell script … with administrator
//       privileges“) EINMAL den System-Passwortdialog. In diesem einen
//       Admin-Kontext passiert beides: die sudoers-Regel wird installiert
//       UND disablesleep sofort auf den gewünschten Wert gesetzt. Danach
//       läuft jeder weitere Schaltvorgang lautlos über Schritt 1.
//
//  Was die Regel erlaubt — und was nicht:
//
//      <kurzname> ALL=(root) NOPASSWD: /usr/bin/pmset
//
//    Genau EIN Binary: /usr/bin/pmset als root, ohne Passwort, nur für den
//    angemeldeten Benutzer. pmset verwaltet ausschließlich Energie-
//    einstellungen — es startet keine Programme, liest keine Dateien fremder
//    Nutzer und eskaliert nichts darüber hinaus. Dieser enge Zuschnitt ist
//    der ganze Sinn der Regel: kein „NOPASSWD: ALL“, kein Shell-Zugriff.
//    Wieder loswerden:  sudo rm /etc/sudoers.d/claude-max-monitor
//
//  Sicherheitsregeln in diesem File:
//    • Der Kurzname (NSUserName()) wird gegen ^[a-z_][a-z0-9_-]*$ geprüft.
//      Passt er nicht, wird KEINE Regel installiert — dann bleibt nur der
//      Admin-Dialog pro Schaltvorgang (pmset direkt, ohne sudoers-Zeile).
//      Niemals wandert ein ungeprüfter String in eine root-Shell.
//    • Die Regel wird erst mit `visudo -cf` validiert und nur bei Erfolg
//      nach /etc/sudoers.d installiert (440, root:wheel) — eine kaputte
//      Datei dort kann sudo systemweit lahmlegen.
//    • Das Passwort sieht ausschließlich der System-Dialog. Die App liest,
//      loggt und speichert nichts dergleichen — hier gibt es schlicht keinen
//      Code-Pfad, der es je zu Gesicht bekäme.
//
//  Thread-Regel: Alle Completions kommen auf dem Main-Thread zurück; die
//  Prozess-Arbeit läuft auf einer eigenen seriellen Queue.
//
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import OSLog

/// Fehlerbild des privilegierten Schaltvorgangs.
enum PrivilegedPowerError: Error {
    /// Der Benutzer hat den System-Passwortdialog abgebrochen.
    case cancelled
    /// Alles andere — Meldung fürs Log, nie fürs Passwort.
    case failed(String)
}

enum PrivilegedPower {

    // MARK: - Konstanten

    private static let pmsetPath = "/usr/bin/pmset"
    private static let sudoersFile = "/etc/sudoers.d/claude-max-monitor"

    private static let queue = DispatchQueue(
        label: "xyz.fi5h.Usage4Claude.privileged-power",
        qos: .userInitiated
    )

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "xyz.fi5h.Usage4Claude",
        category: "PrivilegedPower"
    )

    // MARK: - Öffentliche API

    /// Setzt `pmset -a disablesleep` — erst still, notfalls mit dem EINEN
    /// Admin-Dialog (siehe Dateikopf). Nur aus einer ausdrücklichen
    /// Benutzeraktion aufrufen (Schalter in der Übersicht), nie beim Start.
    static func setSleepDisabled(_ on: Bool, completion: @escaping (Result<Void, PrivilegedPowerError>) -> Void) {
        queue.async {
            if runSilently(on) {
                DispatchQueue.main.async { completion(.success(())) }
                return
            }
            let result = runInteractively(on)
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Nur der stille Weg (`sudo -n`) — für den Start der App (Re-Apply des
    /// gemerkten Schalters) und andere Stellen, an denen NIEMALS ein
    /// Passwortdialog erscheinen darf. Regel installiert → wirkt; Regel
    /// fehlt → still übersprungen, `false`.
    static func setSleepDisabledSilently(_ on: Bool, completion: ((Bool) -> Void)? = nil) {
        queue.async {
            let ok = runSilently(on)
            if let completion {
                DispatchQueue.main.async { completion(ok) }
            }
        }
    }

    /// Synchrone Variante des stillen Wegs — einzig fürs Beenden der App
    /// gedacht (applicationWillTerminate wartet nicht auf Queues). `sudo -n`
    /// antwortet in Millisekunden, mit wie ohne Regel.
    @discardableResult
    static func setSleepDisabledSilentlyAndWait(_ on: Bool) -> Bool {
        runSilently(on)
    }

    // MARK: - Stiller Weg

    /// `sudo -n pmset …`: gelingt genau dann, wenn die Einmal-Regel
    /// installiert ist. Kein Dialog, keine Rückfrage — `-n` bricht sonst
    /// sofort ab.
    private static func runSilently(_ on: Bool) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", pmsetPath, "-a", "disablesleep", on ? "1" : "0"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            log.notice("sudo -n ließ sich nicht starten: \(error.localizedDescription, privacy: .public)")
            return false
        }
        process.waitUntilExit()

        let ok = process.terminationStatus == 0
        if ok {
            log.notice("disablesleep still auf \(on ? "1" : "0", privacy: .public) gesetzt")
        }
        return ok
    }

    // MARK: - Einmal-Freigabe (interaktiv)

    /// Der EINE Admin-Dialog: installiert die sudoers-Regel und setzt
    /// disablesleep im selben Aufruf. Läuft blockierend auf `queue`.
    private static func runInteractively(_ on: Bool) -> Result<Void, PrivilegedPowerError> {
        let value = on ? "1" : "0"
        let user = NSUserName()
        let shell: String

        if isValidShortUserName(user) {
            // Regel + Schaltvorgang in EINEM Admin-Kontext. `set -e` bricht
            // beim ersten Fehler ab: scheitert visudo, wird nichts
            // installiert und pmset nicht ausgeführt.
            let rule = "\(user) ALL=(root) NOPASSWD: \(pmsetPath)"
            shell = [
                "set -e",
                "umask 077",
                "tmp=$(/usr/bin/mktemp /private/tmp/claude-max-monitor-sudoers.XXXXXX)",
                "/usr/bin/printf '%s\\n' '\(rule)' > \"$tmp\"",
                "/usr/sbin/visudo -cf \"$tmp\"",
                "/usr/bin/install -m 440 -o root -g wheel \"$tmp\" \(sudoersFile)",
                "/bin/rm -f \"$tmp\"",
                "\(pmsetPath) -a disablesleep \(value)"
            ].joined(separator: "; ")
        } else {
            // Kurzname außerhalb des sicheren Musters: KEINE Regel
            // installieren (nichts Ungeprüftes in eine root-Shell) — dann
            // eben ein Admin-Dialog pro Schaltvorgang.
            log.notice("Kurzname passt nicht ins sudoers-Muster — Einmal-Regel wird nicht installiert")
            shell = "\(pmsetPath) -a disablesleep \(value)"
        }

        let script = "do shell script \(appleScriptStringLiteral(shell)) with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = Pipe()
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return .failure(.failed("osascript ließ sich nicht starten: \(error.localizedDescription)"))
        }

        // Erst die Pipe leer lesen, dann warten — sonst kann ein voller
        // Puffer beide Seiten festhalten.
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            log.notice("Einmal-Freigabe erteilt, disablesleep auf \(value, privacy: .public) gesetzt")
            return .success(())
        }

        let message = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Abbruch im Passwortdialog: osascript endet mit Status 1 und
        // AppleScript-Fehler -128 („User canceled“ — lokalisiert, die Nummer
        // bleibt). Das ist kein Fehler, sondern eine Entscheidung.
        if message.contains("-128") {
            log.notice("Einmal-Freigabe abgebrochen — Deckel-Schutz bleibt aus")
            return .failure(.cancelled)
        }

        log.error("Einmal-Freigabe fehlgeschlagen: \(message, privacy: .public)")
        return .failure(.failed(message))
    }

    // MARK: - Validierung & Escaping

    /// Klassisches POSIX-Kurznamen-Muster. Alles außerhalb (Leerzeichen,
    /// Quotes, Unicode …) fliegt raus — solche Namen kommen NIE in die Regel.
    static func isValidShortUserName(_ name: String) -> Bool {
        name.range(of: "^[a-z_][a-z0-9_-]*$", options: .regularExpression) != nil
    }

    /// Baut ein AppleScript-String-Literal: Backslashes zuerst, dann
    /// Anführungszeichen — die einzigen zwei Zeichen, die AppleScript in
    /// "…" interpretiert.
    static func appleScriptStringLiteral(_ raw: String) -> String {
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
