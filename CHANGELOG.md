# Änderungen

## 1.1

- Neues App-Symbol: Wasserstand im Ring, passend zur Übersicht. Wird über
  `scripts/make_icon.swift` gezeichnet, statt als Binärdatei mitzureisen.

## 1.0

Erste Veröffentlichung dieses Forks.

- Mehrkonten-Übersicht: alle Claude- und Codex-Konten gleichzeitig, eine Karte pro Zugang
- Wochenlimit als große Leitzahl, Sitzungsfenster als Wasserstand mit zweifarbiger Zahl
- Vierstufige Farbskala von Blau bis Rot
- Countdown bei Freischaltung in unter drei Tagen, Datum darüber
- Anmelde-Email auf der Karte
- Anmeldung im App-Fenster per Cookie-Session als Alternative zum OAuth-Weg
- Build ohne Xcode über `scripts/build_without_xcode.sh`
- Selbst gehostete Updates über `scripts/release.sh`, stündliche Prüfung
- Oberfläche auf Deutsch und Englisch
