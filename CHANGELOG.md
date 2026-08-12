# Änderungen

## 1.2

- Nur noch die Gesamtübersicht: Die Einzelansicht ist entfallen, ein Klick auf das
  Menüleistensymbol zeigt immer alle Konten. Ohne Konten führt ein schlichter
  Hinweis zum Hinzufügen.
- Ampelzeile über den Karten: ein Punkt je Konto, eingefärbt nach dem Wochenlimit
  (grün bis rot, grau ohne Daten) — der Blick genügt, um zu sehen, wo noch Luft ist.
- Konten sortieren sich nach freier Kapazität; fast erschöpfte (ab 96 %) werden
  gedämpft dargestellt und rutschen nach unten. Beim Überfahren kommen sie zurück.
- Fable-Wochenlimit als eigenständiges Limit mit eigener Farbe und Form, in den
  Anzeigeoptionen wählbar und in der Menüleiste darstellbar. Wochenlimits werden
  jetzt am Modellnamen erkannt statt an der Position.
- Restzeit auf den Karten größer und kräftiger gesetzt.
- Weniger „Zu viele Anfragen": Abfragen mehrerer Konten sind stärker entzerrt, und
  ein Limit überschreibt vorhandene Daten nicht mehr mit einer Fehlermeldung.
- Beim Hinzufügen eines Kontos erzwingt die Anmeldung eine frische Sitzung — zuvor
  konnte ein zweites Konto die Kennung des bereits angemeldeten übernehmen.
- Die App heißt durchgehend Claude Max Monitor; Reste des ursprünglichen Namens sind
  verschwunden.

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
