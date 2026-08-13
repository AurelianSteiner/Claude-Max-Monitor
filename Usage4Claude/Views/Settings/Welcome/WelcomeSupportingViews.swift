//
//  WelcomeSupportingViews.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//
//  小型可复用组件，从 WelcomeView.swift 拆出以保持单文件体量可控.
//  Die Menüleisten-Vorschau und die horizontale Radio-Gruppe sind mit den
//  Anzeige-Optionen des Einrichtungs-Schritts entfallen.

import SwiftUI

// MARK: - Navigation Buttons

struct NavigationButtons: View {
    let currentStep: WelcomeView.WelcomeStep
    let canProceed: Bool
    let isFetchingOrgId: Bool
    let fetchError: String?
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // 错误提示
            if let error = fetchError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            // 按钮行
            HStack(spacing: 12) {
                // 返回按钮
                if currentStep != .welcome {
                    Button(action: onBack) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text(L.Welcome.back)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isFetchingOrgId)
                }

                Spacer()

                // 跳过按钮
                if currentStep != .setup {
                    Button(L.Welcome.skip, action: onSkip)
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .disabled(isFetchingOrgId)
                }

                // 继续/完成按钮
                Button(action: currentStep == .setup ? onComplete : onNext) {
                    HStack(spacing: 8) {
                        if isFetchingOrgId && currentStep == .setup {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 12, height: 12)
                            Text(L.Welcome.configuring)
                        } else {
                            Text(currentStep == .setup ? L.Welcome.finish : L.Welcome.continue_)
                            if currentStep != .setup {
                                Image(systemName: "chevron.right")
                            }
                        }
                    }
                    .frame(maxWidth: 150)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed || isFetchingOrgId)
            }
        }
    }
}
