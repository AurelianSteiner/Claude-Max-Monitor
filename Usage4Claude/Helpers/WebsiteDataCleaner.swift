//
//  WebsiteDataCleaner.swift
//  Usage4Claude
//
//  Räumt Anmelde-Cookies aus den beiden Cookie-Töpfen, die der Prozess auf die
//  Platte schreibt:
//
//    • WKWebsiteDataStore.default() — der prozessweite WebKit-Store
//      (~/Library/WebKit/…), in den die stille Codex-Erneuerung
//      (CodexSilentRefreshCoordinator) ihr Sitzungs-Token einspritzt.
//    • HTTPCookieStorage.shared — der Topf der URLSession-Pfade
//      (~/Library/Cookies/…), in dem Set-Cookie-Antworten landen.
//
//  Beide überleben das Entfernen eines Kontos, das nur den Schlüsselbund
//  umschreibt. Ein noch gültiges Sitzungs-Token bliebe dort unbegrenzt liegen —
//  lesbar für jeden Prozess des Benutzers, mitgesichert in jedem Backup.
//
//  Gelöscht wird gezielt, nicht pauschal: nur Cookies, die tatsächlich
//  Zugangsdaten tragen (`sessionKey` bzw. `*session-token*`). Die
//  Cloudflare-Nachweise (cf_clearance/__cf_bm) bleiben ausdrücklich liegen —
//  ohne sie liefen die nächsten Anfragen in die Bot-Prüfung.
//
//  MEHRERE KONTEN desselben Anbieters: Beide Töpfe sind prozessweit und kennen
//  keine Konten; pro Domain und Cookie-Name existiert ohnehin nur EIN Eintrag,
//  es gibt also nichts kontobezogen auszusortieren. Ein verbleibendes Konto
//  verliert dadurch trotzdem nichts: Die Zugangsdaten stehen im Schlüsselbund,
//  und beide Codex-Erneuerungspfade schicken bzw. spritzen das Token des
//  aktuellen Kontos vor jeder Anfrage neu ein.
//
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import OSLog
import WebKit

enum WebsiteDataCleaner {

    /// Marker: Die Altlast aus früheren Versionen (siehe `purgeLegacyClaudeCookiesOnce`)
    /// ist weg — nie wieder nachsehen.
    private static let legacyClaudePurgeMarker = "didPurgeLegacyClaudeWebKitCookies"

    // MARK: - Public

    /// Entfernt die Anmelde-Cookies des Anbieters aus BEIDEN Töpfen.
    /// Beim Entfernen eines Kontos aufzurufen; darf von jedem Thread kommen.
    static func removeCredentialCookies(for provider: ProviderType) {
        removeFromSharedCookieStorage(provider)
        Task { @MainActor in removeFromWebKitStore(provider) }
    }

    /// Nur der WebKit-Store. Für die stille Codex-Erneuerung, die ihr Token vor
    /// jedem Laden frisch einspritzt und es danach nicht liegen lassen muss.
    @MainActor
    static func removeCredentialCookiesFromWebKitStore(for provider: ProviderType) {
        removeFromWebKitStore(provider)
    }

    /// Einmaliger Nachlauf für Bestandsinstallationen: Frühere Versionen kopierten
    /// den claude.ai-`sessionKey` nach erfolgreicher Cookie-Anmeldung in den
    /// WebKit-Store. Diese Kopie hatte nie einen Leser und wird nicht mehr
    /// angelegt — ohne aktives Aufräumen läge sie aber bis zum Entfernen des
    /// Kontos dort, also unter Umständen für immer.
    static func purgeLegacyClaudeCookiesOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: legacyClaudePurgeMarker) else { return }

        Task { @MainActor in
            removeFromWebKitStore(.claude) {
                defaults.set(true, forKey: legacyClaudePurgeMarker)
            }
        }
    }

    // MARK: - Private

    /// Trägt das Cookie Zugangsdaten? Cloudflare-Nachweise fallen bewusst NICHT
    /// darunter, siehe Kopfkommentar.
    private static func isCredentialCookie(_ cookie: HTTPCookie, of provider: ProviderType) -> Bool {
        switch provider {
        case .claude:
            return cookie.domain.contains("claude.ai") && cookie.name.contains("sessionKey")
        case .codex:
            let isProviderDomain = cookie.domain.contains("chatgpt.com") || cookie.domain.contains("openai.com")
            // Deckt auch die NextAuth-Scherben `…session-token.0/.1/…` ab
            return isProviderDomain && cookie.name.contains("session-token")
        }
    }

    private static func removeFromSharedCookieStorage(_ provider: ProviderType) {
        let storage = HTTPCookieStorage.shared
        let stale = (storage.cookies ?? []).filter { isCredentialCookie($0, of: provider) }
        guard !stale.isEmpty else { return }

        for cookie in stale { storage.deleteCookie(cookie) }
        Logger.settings.notice("WebsiteDataCleaner: \(stale.count) \(provider.displayName)-Cookie(s) aus HTTPCookieStorage entfernt")
    }

    @MainActor
    private static func removeFromWebKitStore(_ provider: ProviderType, completion: (() -> Void)? = nil) {
        let store = WKWebsiteDataStore.default().httpCookieStore
        store.getAllCookies { cookies in
            let stale = cookies.filter { isCredentialCookie($0, of: provider) }
            guard !stale.isEmpty else {
                completion?()
                return
            }

            let group = DispatchGroup()
            for cookie in stale {
                group.enter()
                store.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) {
                Logger.settings.notice("WebsiteDataCleaner: \(stale.count) \(provider.displayName)-Cookie(s) aus dem WebKit-Store entfernt")
                completion?()
            }
        }
    }
}
