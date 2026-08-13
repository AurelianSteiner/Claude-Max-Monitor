//
//  SetupStepView.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

// MARK: - Setup Step (Authentication)
// 从 WelcomeView.swift 拆出，便于保持单文件体量可控。
// Die früheren Anzeige-Optionen (Symbol/Prozent, Limit-Auswahl) sind entfallen:
// Die Menüleiste zeigt fest einen Punkt je Konto, da gibt es nichts einzurichten.

struct SetupStepView: View {
    @Binding var sessionKey: String
    @Binding var isShowingPassword: Bool
    @ObservedObject private var settings = UserSettings.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 紧凑的欢迎信息
                VStack(spacing: 8) {
                    if let icon = ImageHelper.createAppIcon(size: 48) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 48, height: 48)
                            .cornerRadius(10)
                    }

                    Text(L.Welcome.title)
                        .font(.title3)
                        .fontWeight(.bold)
                }
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider()
                    .padding(.vertical, 20)

                // 主设置区域
                VStack(alignment: .leading, spacing: 20) {
                    // SessionKey 设置
                    VStack(alignment: .leading, spacing: 12) {
                        // 标题
                        HStack(spacing: 8) {
                            Image(systemName: "key.fill")
                                .font(.title3)
                                .foregroundColor(.blue)
                            Text(L.Welcome.authenticationSetup)
                                .font(.headline)

                            Spacer()

                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "person.2.fill")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(L.Welcome.multiAccountHint)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // 浏览器登录按钮（推荐）
                        Button(action: {
                            WebLoginWindowManager.shared.showLoginWindow { account in
                                // 登录成功后自动填充 sessionKey
                                sessionKey = account.sessionKey
                            }
                        }) {
                            HStack {
                                Image(systemName: "globe")
                                Text(L.WebLogin.browserLoginRecommended)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        // 分隔线
                        HStack {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(height: 1)
                            Text(L.WebLogin.orManualInput)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .layoutPriority(1)
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(height: 1)
                        }

                        // Session Key输入 - 横向
                        HStack(alignment: .top, spacing: 12) {
                            Text(L.Welcome.sessionKey)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(width: 100, alignment: .leading)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    if isShowingPassword {
                                        TextField(L.Welcome.sessionKeyPlaceholder, text: $sessionKey)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(.body, design: .monospaced))
                                    } else {
                                        SecureField(L.Welcome.sessionKeyPlaceholder, text: $sessionKey)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(.body, design: .monospaced))
                                    }

                                    Button(action: {
                                        isShowingPassword.toggle()
                                    }) {
                                        Image(systemName: isShowingPassword ? "eye.slash.fill" : "eye.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                // 验证状态
                                if !sessionKey.isEmpty {
                                    if settings.isValidSessionKey(sessionKey) {
                                        Label(L.Welcome.validFormat, systemImage: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    } else {
                                        Label(L.Welcome.invalidFormat, systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }

                                Text(L.Welcome.sessionKeyHint)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                // 帮助按钮
                                Button(action: {
                                    if let url = URL(string: setupReadmeURL) {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "questionmark.circle")
                                        Text(L.Welcome.howToGetSessionKey)
                                            .font(.caption)
                                    }
                                    .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 40)

                Spacer(minLength: 20)
            }
        }
    }

    // MARK: - GitHub README URL Helper

    /// Link auf den Einrichtungs-Abschnitt der README in der gewählten Sprache
    private var setupReadmeURL: String {
        let baseURL = "https://github.com/AurelianSteiner/Claude-Max-Monitor/blob/main"

        switch settings.language {
        case .english:
            return "\(baseURL)/README.md#initial-setup"
        case .german:
            return "\(baseURL)/docs/README.de.md#erste-konfiguration"
        }
    }
}
