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
//
//  Unter jeder Wochen-Zeile liegt eine kleine 7-Tage-Verlaufslinie
//  (`TeamSparkline`), sobald der Verlauf der Person geladen ist — geholt
//  wird er träge beim Öffnen des Details (`TeamHistoryStore`).
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

struct TeamMemberDetailView: View {
    let report: TeamReport
    /// Zurück zur Liste — die Ansicht lebt im selben Container wie sie
    var onBack: () -> Void

    @ObservedObject private var historyStore = TeamHistoryStore.shared

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

    /// Der geladene Verlauf dieser Person — `nil`, solange er noch fehlt
    private var samples: [TeamHistorySample]? {
        historyStore.samples(for: report.historyMemberId)
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
        .onAppear { historyStore.load(memberId: report.historyMemberId) }
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

            // Eine Fußnote für alle Linien, statt einer Beschriftung an
            // jeder — die Linien selbst bleiben unbeschriftet und ruhig.
            if showsAnySparkline {
                Text(L.Team.detailHistory)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
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
    /// Tooltip war sie versteckt. Wochen-Zeilen tragen darunter ihre
    /// 7-Tage-Verlaufslinie, sobald der Verlauf geladen ist.
    @ViewBuilder
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
                .frame(width: Self.resetWidth, alignment: .trailing)
        }

        if let points = sparklinePoints(for: limit) {
            sparklineRow(points, percent: limit.percent)
        }
    }

    // MARK: - Verlaufslinien

    /// Breite der Reset-Spalte rechts neben dem Balken
    private static let resetWidth: CGFloat = 68

    /// Die Verlaufspunkte einer Zeile — nur für Wochen-Zeilen, und nur wenn
    /// mindestens zwei Punkte da sind (ein einzelner ergäbe keine Linie).
    /// Das Sitzungsfenster bekommt bewusst keine Linie: Es springt alle fünf
    /// Stunden auf null, sein „Verlauf" wäre ein Sägezahn ohne Aussage.
    private func sparklinePoints(for limit: TeamLimit) -> [TeamHistoryPoint]? {
        guard TeamSummary.isWeekly(limit), let samples else { return nil }
        let points = samples.points(label: limit.label)
        return points.count >= 2 ? points : nil
    }

    /// Die Linie unter einer Zeile, exakt unter deren Balken ausgerichtet:
    /// links die Beschriftungs-, rechts die Wert- und Reset-Spalte freigehalten.
    private func sparklineRow(_ points: [TeamHistoryPoint], percent: Int) -> some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: TeamLimitBar.labelWidth, height: 1)
            TeamSparkline(points: points, percent: percent)
                .frame(height: 18)
                .help(L.Team.detailHistory)
            Color.clear.frame(width: TeamLimitBar.valueWidth, height: 1)
            Color.clear.frame(width: Self.resetWidth, height: 1)
        }
        .padding(.bottom, 2)
    }

    /// Zeigt mindestens eine Zeile eine Verlaufslinie? (Für die Fußnote.)
    private var showsAnySparkline: Bool {
        report.limits.contains { sparklinePoints(for: $0) != nil }
    }
}
