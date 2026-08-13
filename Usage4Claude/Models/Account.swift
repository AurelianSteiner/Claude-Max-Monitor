//
//  Account.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-02-05.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// Firmen- oder Privatkonto. Firma und privates Abo können auf derselben Email
/// liegen — dann sind zwei Karten sonst nicht auseinanderzuhalten.
/// `.unknown` heißt bewusst „wir wissen es nicht": Die Karte zeigt dann gar
/// nichts, statt zu raten. Der Nutzer kann in den Einstellungen nachhelfen.
enum AccountKind: String, Codable, CaseIterable {
    case personal
    case company
    case unknown

    /// SF-Symbol neben dem Kontonamen; `nil` = nichts anzeigen.
    var symbolName: String? {
        switch self {
        case .company:  return "building.2"
        case .personal: return "person"
        case .unknown:  return nil
        }
    }

    var localizedName: String {
        switch self {
        case .company:  return L.Account.kindCompany
        case .personal: return L.Account.kindPersonal
        case .unknown:  return L.Account.kindUnknown
        }
    }
}

struct Account: Codable, Identifiable, Equatable {
    let id: UUID
    var sessionKey: String
    var organizationId: String
    var organizationName: String
    var alias: String?
    let createdAt: Date
    var provider: ProviderType
    /// Anmelde-Email des Kontos, sofern die Login-Route sie liefert
    /// (Claude-OAuth-Profil, Codex-ID-Token). Bei reinen Cookie-Konten leer.
    var email: String?
    /// Firma oder privat. Beim Login bestmöglich erkannt, in den Einstellungen
    /// überschreibbar — die manuelle Angabe ist die verlässliche Quelle.
    var kind: AccountKind

    var displayName: String {
        if let alias = alias, !alias.isEmpty {
            return alias
        }
        return organizationName
    }

    /// Zweite Zeile auf der Dashboard-Karte: die Email, aber nur wenn sie nicht
    /// ohnehin schon als Titel dasteht (bei OAuth-Konten ohne Alias ist der
    /// organizationName die Email — dann wäre es eine doppelte Zeile).
    var secondaryLabel: String? {
        guard let email, !email.isEmpty, email != displayName else { return nil }
        return email
    }

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case id, sessionKey, organizationId, organizationName, alias, createdAt, provider, email, kind
    }

    // MARK: - Codable

    // 自定义解码：旧版 JSON 不含 provider 字段时默认为 .claude，确保旧账号数据零迁移
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sessionKey = try container.decode(String.self, forKey: .sessionKey)
        organizationId = try container.decode(String.self, forKey: .organizationId)
        organizationName = try container.decode(String.self, forKey: .organizationName)
        alias = try container.decodeIfPresent(String.self, forKey: .alias)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        provider = try container.decodeIfPresent(ProviderType.self, forKey: .provider) ?? .claude
        // Ältere Konten kennen das Feld nicht. Bei OAuth-Logins stand die Email
        // bisher im organizationName — von dort übernehmen, statt sie zu verlieren.
        let decodedEmail = try container.decodeIfPresent(String.self, forKey: .email)
        if let decodedEmail, !decodedEmail.isEmpty {
            email = decodedEmail
        } else {
            email = organizationName.contains("@") ? organizationName : nil
        }
        // Bestehende Konten kennen das Feld nicht — und ein unbekannter Wert
        // (z. B. aus einer neueren Version) darf das Laden nicht sprengen.
        let decodedKind = (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? nil
        kind = decodedKind.flatMap(AccountKind.init(rawValue:)) ?? .unknown
    }

    // MARK: - Initialization

    init(
        sessionKey: String,
        organizationId: String,
        organizationName: String,
        alias: String? = nil,
        provider: ProviderType = .claude,
        email: String? = nil,
        kind: AccountKind = .unknown
    ) {
        self.id = UUID()
        self.sessionKey = sessionKey
        self.organizationId = organizationId
        self.organizationName = organizationName
        self.alias = alias
        self.createdAt = Date()
        self.provider = provider
        self.email = (email?.isEmpty == false) ? email : (organizationName.contains("@") ? organizationName : nil)
        self.kind = kind
    }

    init(
        id: UUID,
        sessionKey: String,
        organizationId: String,
        organizationName: String,
        alias: String?,
        createdAt: Date,
        provider: ProviderType = .claude,
        email: String? = nil,
        kind: AccountKind = .unknown
    ) {
        self.id = id
        self.sessionKey = sessionKey
        self.organizationId = organizationId
        self.organizationName = organizationName
        self.alias = alias
        self.createdAt = createdAt
        self.provider = provider
        self.email = (email?.isEmpty == false) ? email : (organizationName.contains("@") ? organizationName : nil)
        self.kind = kind
    }

    // MARK: - Equatable

    static func == (lhs: Account, rhs: Account) -> Bool {
        return lhs.id == rhs.id
    }
}
