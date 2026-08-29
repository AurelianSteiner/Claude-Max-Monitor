//
//  DashboardMode.swift
//  Usage4Claude
//
//  Welcher Inhalt in der Übersicht steht: das Konten-Gitter oder die
//  Team-Ansicht. Bewusst EIN geteilter Zustand für Popover und Fenster —
//  beide zeigen dieselbe Übersicht, also auch denselben Modus; wer im
//  Popover zum Team wechselt, findet das Fenster genauso vor.
//
//  Früher war die Team-Ansicht ein drittes eigenes Fenster
//  (TeamWindowManager) — ein Fenster zu viel: Sie ist jetzt ein Modus der
//  Übersicht, erreichbar über den Kopfzeilen-Knopf.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Combine

final class DashboardMode: ObservableObject {
    static let shared = DashboardMode()

    /// true = Team-Ansicht, false = Konten-Gitter
    @Published var showsTeam = false

    private init() {}
}
