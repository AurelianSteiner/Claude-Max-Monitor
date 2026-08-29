//
//  TeamMemberDetailView.swift
//  Usage4Claude
//
//  Die Detailansicht einer Person aus der Team-Liste: oben die beiden großen
//  Fragen (Sitzung? Woche?) in derselben Bildsprache wie die eigenen
//  Kontokarten — Wasserstand für die Sitzung, große Prozentzahl für die
//  Woche —, darunter jede gemeldete Limit-Zeile mit sichtbarer Reset-Zeit.
//
//  Die Zeilen sind nach ihrer Art gruppiert (Sitzung/Woche, Modelle, weitere
//  Konten), sofern die Meldung das maschinenlesbare `kind`-Feld trägt. Alte
//  Meldungen ohne `kind` zeigen schlicht alle Zeilen in Meldereihenfolge.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

struct TeamMemberDetailView: View {
    let report: TeamReport
    /// Zurück zur Liste — die Ansicht lebt im selben Container wie sie
    var onBack: () -> Void

    private var sessionLimit: TeamLimit? {
        report.limits.first(where: TeamSummary.isSession)
    }

    private var weeklyPercent: Int? {
        TeamSummary.weeklyPercent(of: report)
    }

    /// Die Wochenzeile des Hauptkontos — für die Reset-Zeit neben der großen Zahl
    private var weeklyLimit: TeamLimit? {
        report.limits.first { $0.kind == .weekly }
            ?? report.limits.first { $0.kind == nil && TeamSummary.isWeekly($0) }
    }

    private var modelLimits: [TeamLimit] {
        report.limits.filter { $0.kind == .modelWeekly }
    }

    private var accountLimits: [TeamLimit] {
        report.limits.filter { $0.kind == .accountWeekly }
    }

    /// Alles, was nicht in den Kopf oder eine benannte Gruppe gehört:
    /// bei alten Meldungen ohne `kind` schlicht alle Zeilen.
    private var baseLimits: [TeamLimit] {
        report.limits.filter { $0.kind == .session || $0.kind == .weekly || $0.kind == nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                backRow
                headline
                Divider()
                limitSections
            }
            .padding(12)
        }
    }

    // MARK: - Kopf

    private var backRow: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L.Team.windowTitle)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)

            Spacer(minLength: 8)

            Text(L.Team.reportedAgo(report.reportedAgoText))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)

            if let stale = report.staleLabel {
                Text(stale)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(DashboardPalette.ink(80))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(DashboardPalette.fill(80).opacity(0.15)))
            }
        }
    }

    /// Name plus die beiden Kernwerte: links der Sitzungs-Wasserstand, rechts
    /// die Wochenlage als große Zahl — dieselbe Zweiteilung wie auf den
    /// eigenen Kontokarten, damit fremde und eigene Zahlen gleich lesbar sind.
    private var headline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(report.person)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 14) {
                if let session = sessionLimit {
                    VStack(spacing: 3) {
                        WaterLevelGauge(
                            percentage: Double(session.percent),
                            caption: L.Dashboard.sessionLimit,
                            diameter: 68
                        )
                        if let reset = session.resetsAtText {
                            Text(reset)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if sessionLimit != nil, weeklyPercent != nil {
                    ProviderDivider(height: 56)
                }

                if let weekly = weeklyPercent {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(weekly)%")
                            .font(.system(size: 30, weight: .bold).monospacedDigit())
                            .foregroundColor(DashboardPalette.ink(Double(weekly)))
                        Text(L.Dashboard.weeklyLimit)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        if let reset = weeklyLimit?.resetsAtText {
                            Text(reset)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .opacity(report.isStale ? 0.55 : 1)
    }

    // MARK: - Limit-Zeilen

    @ViewBuilder
    private var limitSections: some View {
        if report.limits.isEmpty {
            // Kann vorkommen: Meldung war gültig, alle Zeilen darin kaputt.
            Text("–")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(baseLimits) { limit in
                    limitRow(limit)
                }
            }

            if !modelLimits.isEmpty {
                section(title: L.Team.detailModels, limits: modelLimits)
            }
            if !accountLimits.isEmpty {
                section(title: L.Team.detailAccounts, limits: accountLimits)
            }
        }
    }

    private func section(title: String, limits: [TeamLimit]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.top, 6)
            ForEach(limits) { limit in
                limitRow(limit)
            }
        }
    }

    /// Eine Limit-Zeile mit **sichtbarer** Reset-Zeit: Die Übersicht ist zum
    /// Planen da, und „ab wann wieder frei" ist die halbe Antwort — im
    /// Tooltip war sie versteckt.
    private func limitRow(_ limit: TeamLimit) -> some View {
        HStack(spacing: 8) {
            TeamLimitBar(
                label: limit.label,
                percent: limit.percent,
                resetsAtText: limit.resetsAtText
            )

            Text(limit.resetsAtText ?? "–")
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 68, alignment: .trailing)
        }
    }
}
