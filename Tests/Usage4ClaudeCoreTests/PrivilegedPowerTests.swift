import XCTest
@testable import Usage4ClaudeCore

/// Abgedecktes Risiko: `PrivilegedPower` schreibt eine sudoers-Regel und baut
/// ein Shell-Kommando, das als root läuft. Lässt die Namensprüfung auch nur
/// EIN Sonderzeichen durch oder escapt das AppleScript-Literal falsch, wird
/// aus einem Benutzernamen eine root-Shell-Injektion. Dazu kommt der Zuschnitt
/// der Regel selbst: ohne Argumentliste verschenkt sie root für jeden
/// pmset-Aufruf. Diese Tests nageln alles drei fest.
final class PrivilegedPowerTests: XCTestCase {

    // MARK: - isValidShortUserName: gültige Kurznamen

    func testAcceptsPlainLowercaseName() {
        XCTAssertTrue(PrivilegedPower.isValidShortUserName("aurelian4"))
    }

    func testAcceptsUnderscorePrefixAndDash() {
        // macOS-Dienstkonten beginnen mit "_", Bindestriche sind erlaubt
        XCTAssertTrue(PrivilegedPower.isValidShortUserName("_svc-user"))
        XCTAssertTrue(PrivilegedPower.isValidShortUserName("a"))
        XCTAssertTrue(PrivilegedPower.isValidShortUserName("_"))
    }

    // MARK: - isValidShortUserName: alles Feindliche fliegt raus

    func testRejectsEmptyName() {
        XCTAssertFalse(PrivilegedPower.isValidShortUserName(""))
    }

    func testRejectsUppercaseAndDot() {
        // Bewusst eng: lieber pro Schaltvorgang fragen als die Regel weiten
        XCTAssertFalse(PrivilegedPower.isValidShortUserName("Abc"))
        XCTAssertFalse(PrivilegedPower.isValidShortUserName("john.doe"))
    }

    func testRejectsLeadingDigitOrDash() {
        XCTAssertFalse(PrivilegedPower.isValidShortUserName("1abc"))
        XCTAssertFalse(PrivilegedPower.isValidShortUserName("-abc"))
    }

    func testRejectsShellAndSudoersMetacharacters() {
        XCTAssertFalse(PrivilegedPower.isValidShortUserName("abc'; rm -rf /; '"))
        XCTAssertFalse(PrivilegedPower.isValidShortUserName("abc ALL=(ALL) NOPASSWD: ALL #"))
        XCTAssertFalse(PrivilegedPower.isValidShortUserName("abc\"x"))
        XCTAssertFalse(PrivilegedPower.isValidShortUserName("abc\\"))
        XCTAssertFalse(PrivilegedPower.isValidShortUserName("abc$USER"))
        XCTAssertFalse(PrivilegedPower.isValidShortUserName("abc`id`"))
    }

    func testRejectsNewlineVariants() {
        // Ein Zeilenumbruch im Namen wäre eine ZWEITE sudoers-Zeile —
        // auch am Ende ($ darf nicht vor einem End-\n matchen)
        XCTAssertFalse(PrivilegedPower.isValidShortUserName("abc\n"))
        XCTAssertFalse(PrivilegedPower.isValidShortUserName("abc\r"))
        XCTAssertFalse(PrivilegedPower.isValidShortUserName("abc\nevil ALL=(ALL) NOPASSWD: ALL"))
    }

    func testRejectsUnicodeLookalikes() {
        // Kyrillisches „а“ statt lateinischem „a“
        XCTAssertFalse(PrivilegedPower.isValidShortUserName("a\u{0430}bc"))
        XCTAssertFalse(PrivilegedPower.isValidShortUserName("äbc"))
    }

    // MARK: - sudoersRule: exakt die zwei Aufrufe, die die App absetzt

    func testRuleGrantsExactlyTheTwoSwitchCommands() {
        XCTAssertEqual(
            PrivilegedPower.sudoersRule(for: "aurelian"),
            "aurelian ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0"
        )
    }

    func testRuleNeverGrantsFreePmset() {
        // Der Kern des Zuschnitts: `/usr/bin/pmset` ohne Argumentliste wäre
        // root für JEDEN pmset-Aufruf — Zeitpläne stellen, den Mac aufwecken,
        // Batterie-Schwellen verstellen. sudoers matcht die Argumente exakt,
        // also muss jeder Eintrag die vollständige Liste tragen.
        let rule = PrivilegedPower.sudoersRule(for: "aurelian")
        let parts = rule.components(separatedBy: "NOPASSWD: ")
        guard parts.count == 2 else { return XCTFail("Regel ohne NOPASSWD-Teil: \(rule)") }

        let commands = parts[1]
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertFalse(commands.contains("/usr/bin/pmset"))
        XCTAssertTrue(commands.allSatisfy { $0.hasPrefix("/usr/bin/pmset -a disablesleep ") })
    }

    func testRuleStaysOnASingleLine() {
        // Eine zweite Zeile in /etc/sudoers.d wäre eine zweite Berechtigung.
        let rule = PrivilegedPower.sudoersRule(for: "_svc-user")
        XCTAssertFalse(rule.contains("\n"))
        XCTAssertFalse(rule.contains("\r"))
    }

    // MARK: - needsRuleUpgrade: die alte, weite Regel ablösen

    func testUpgradesWhenOnlyPmsetIsPasswordless() {
        // `sudo -n pmset -g` läuft durch, `sudo -n true` nicht: das kann nur
        // die alte Regel ohne Argumentliste sein — sie muss ersetzt werden,
        // sonst bleibt sie liegen (der stille Weg gelingt mit ihr ja weiter).
        XCTAssertTrue(PrivilegedPower.needsRuleUpgrade(
            pmsetAllowedWithoutRuleArguments: true,
            anyCommandAllowedWithoutPassword: false
        ))
    }

    func testNoUpgradeWithNarrowRuleOrNoRule() {
        // Die enge Regel deckt `pmset -g` nicht ab — genau wie gar keine Regel.
        XCTAssertFalse(PrivilegedPower.needsRuleUpgrade(
            pmsetAllowedWithoutRuleArguments: false,
            anyCommandAllowedWithoutPassword: false
        ))
    }

    func testNoUpgradeWhenEverythingIsPasswordlessAnyway() {
        // Pauschales `NOPASSWD: ALL` des Benutzers: dann sagt die pmset-Probe
        // nichts über UNSERE Regel aus. Ein „Upgrade“ brächte hier nur einen
        // Passwortdialog pro Schaltvorgang und keinen Sicherheitsgewinn.
        XCTAssertFalse(PrivilegedPower.needsRuleUpgrade(
            pmsetAllowedWithoutRuleArguments: true,
            anyCommandAllowedWithoutPassword: true
        ))
        XCTAssertFalse(PrivilegedPower.needsRuleUpgrade(
            pmsetAllowedWithoutRuleArguments: false,
            anyCommandAllowedWithoutPassword: true
        ))
    }

    // MARK: - appleScriptStringLiteral

    func testWrapsPlainStringInQuotes() {
        XCTAssertEqual(PrivilegedPower.appleScriptStringLiteral("pmset"), "\"pmset\"")
    }

    func testEscapesQuotes() {
        XCTAssertEqual(
            PrivilegedPower.appleScriptStringLiteral(#"echo "$tmp""#),
            #""echo \"$tmp\"""#
        )
    }

    func testEscapesBackslashesBeforeQuotes() {
        // Reihenfolge ist die halbe Sicherheit: erst \ verdoppeln, dann "
        // escapen — sonst würde aus »\"« ein unescaptes »\\"« (String-Ende).
        XCTAssertEqual(
            PrivilegedPower.appleScriptStringLiteral(#"\""#),
            #""\\\"""#
        )
        XCTAssertEqual(
            PrivilegedPower.appleScriptStringLiteral(#"printf '%s\n'"#),
            #""printf '%s\\n'""#
        )
    }

    func testLiteralCannotBreakOutOfQuotes() {
        // Kein noch so fieser Input darf ein unescaptes »"« erzeugen:
        // im Ergebnis ist jedes »"« (außer Anfang/Ende) von einer UNGERADEN
        // Zahl Backslashes eingeleitet.
        let hostile = #""; do shell script "id" -- \"; \\"; \\\""#
        let literal = PrivilegedPower.appleScriptStringLiteral(hostile)
        XCTAssertTrue(literal.hasPrefix("\""))
        XCTAssertTrue(literal.hasSuffix("\""))

        let inner = literal.dropFirst().dropLast()
        var backslashRun = 0
        for character in inner {
            if character == "\\" {
                backslashRun += 1
            } else {
                if character == "\"" {
                    XCTAssertEqual(backslashRun % 2, 1, "unescaptes Anführungszeichen in \(literal)")
                }
                backslashRun = 0
            }
        }
    }
}
