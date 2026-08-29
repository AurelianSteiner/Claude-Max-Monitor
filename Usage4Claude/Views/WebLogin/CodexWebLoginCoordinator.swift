//
//  CodexWebLoginCoordinator.swift
//  Usage4Claude
//
//  Created by f-is-h on 2026-04-24.
//  Copyright © 2025 f-is-h. All rights reserved.
//
//  Früher der komplette interaktive WKWebView-Cookie-Login für Codex.
//  Der Login läuft längst über OAuth (CodexOAuthLoginView); übrig bleibt
//  nur der Cookie-Parser, den die stille Token-Auffrischung weiter braucht
//  (CodexSilentRefreshCoordinator, CodexTokenRefreshCoordinator,
//  CodexAPIService).
//

import Foundation

enum CodexWebLoginCoordinator {

    /// 从 chatgpt.com Cookie 列表中提取 session token 值
    /// 支持标准名称、无 __Secure- 前缀版本，以及 next-auth 分片 Cookie（.0/.1/...）
    static func extractSessionToken(from cookies: [HTTPCookie]) -> String? {
        let baseNames = ["__Secure-next-auth.session-token", "next-auth.session-token"]

        for baseName in baseNames {
            if let cookie = cookies.first(where: { $0.name == baseName }) {
                return cookie.value
            }
            let chunks = cookies
                .filter { cookie in
                    guard cookie.name.hasPrefix(baseName + ".") else { return false }
                    let suffix = cookie.name.dropFirst(baseName.count + 1)
                    return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
                }
                .sorted {
                    let ia = Int($0.name.dropFirst(baseName.count + 1)) ?? 0
                    let ib = Int($1.name.dropFirst(baseName.count + 1)) ?? 0
                    return ia < ib
                }
            if !chunks.isEmpty {
                return chunks.map(\.value).joined()
            }
        }
        return nil
    }
}
