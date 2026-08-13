# Änderungen

## 1.7

- Die Karte kennt nur noch zwei Sperrzustände. Eine gesperrte Woche schließt das
  Sitzungsfenster ohnehin ein, deshalb entfällt „Alles gesperrt".
- Neben den beiden Symbolen zum Wachhalten steht jetzt ein kurzes Wort, sodass
  ohne Mauszeiger klar ist, was sie tun.
- Accounts lassen sich als Firma oder privat markieren und zeigen ein passendes
  Symbol neben dem Namen. Die Anmeldung versucht die Art aus dem Profil zu lesen
  und lässt sie andernfalls offen, statt zu raten.

## 1.6

- Die Meldung „neue Version verfügbar" verschwindet endlich. Die App trug intern
  dauerhaft die Nummer 1.0, weshalb der Update-Dienst dieselbe Fassung endlos
  angeboten hat.
- Die Einstellungen enthalten nur noch, was gebraucht wird. Die Menüleiste zeigt
  fest einen Punkt je Account; Symbol- und Prozentauswahl, die Limit-Kästchen,
  der Verbindungstest, die Session-Key-Anleitung und die Kontoauswahl sind
  entfallen. Bestehende Installationen werden auf die Punkte umgestellt.
- Die Schalter zum Wachhalten stehen nur noch als Symbole in der Übersicht. Ihre
  Kurzinfo erklärt jetzt, was sie bewirken — und dass ein geschlossener Deckel den
  Mac weiterhin schlafen legt.
- Die Karten benennen, was gesperrt ist: die Sitzung, die Woche oder alles. Der
  Countdown zählt zu genau dem Limit, das im Text steht.
- Zwischen Warnschwelle und wirklich aufgebrauchtem Fenster sagt die Kurzinfo der
  Punkte „fast aufgebraucht".

## 1.5

- Die beiden Schalter zum Wachhalten sitzen jetzt als Symbole oben in der
  Übersicht. Ein Klick genügt, der Zustand ist sichtbar.
- Das Übersichtsfenster ordnet die Karten nach seiner Breite: schmal gezogen
  stapeln sie sich in einer Spalte, breit gezogen verteilen sie sich auf mehrere.
  Die Spaltenauswahl im Menü setzt die Fensterbreite entsprechend.
- Die Punkte in der Menüleiste stehen in derselben Reihenfolge wie die Karten in
  der Übersicht und ordnen sich mit, wenn die Sortierung wechselt.

## 1.4

- Die Punkte oben zeigen jetzt beide Fenster auf einmal: Die Füllung folgt dem
  Wochenlimit — grün bis fünf Prozent, blau während der Nutzung, rot ab neunzig
  Prozent — und ein roter Ring markiert ein aufgebrauchtes Fünf-Stunden-Fenster.
  Der Tooltip nennt beide Werte.
- Neue Anzeigeart für die Menüleiste: ein Punkt je Konto statt der Ringe. Das ist
  schmal genug, um neben der Notch nicht zu verschwinden.
- Die Schalter zum Wachhalten stehen auch im Menü der Übersicht, nicht mehr nur
  im Rechtsklick-Menü.
- Über-Fenster, Einrichtungshilfe und Diagnosebericht verweisen auf dieses
  Projekt; die letzten Reste des früheren Produktnamens sind verschwunden.

## 1.3

- Fast erschöpfte Konten werden nicht mehr ausgegraut. Stattdessen läuft auf der
  Karte ein Countdown, der zeigt, wann das Limit wieder frei ist.
- Der Kopf der Karte trennt Stunden- und Wochenlimit durch einen Strich, beide
  beschriftet und jeweils mit eigener Restzeit. Die Restzeit des
  Fünf-Stunden-Fensters fehlte bisher ganz.
- Wochenlimits einzelner Modelle (Fable, Opus, Sonnet) erscheinen als
  Prozentbalken ohne Uhrzeit statt als Symbol.
- Die Ampelpunkte oben folgen einer klareren Regel: grün bis fünf Prozent, blau
  während der Nutzung, rot ab hundert Prozent, grau ohne Daten.
- Die Version steht unten in der Übersicht.
- Das Übersichtsfenster lässt sich in der Größe ziehen und merkt sich Lage und
  Größe. Es wird breiter, sobald mehr Spalten nötig sind.
- Zwei Schalter im Menü halten Bildschirm oder Mac wach. Sie überstehen einen
  Neustart der App und brauchen keine Administratorrechte.
- Ein Klick auf die App im Dock, im Finder oder über Spotlight öffnet die
  Übersicht, statt scheinbar nichts zu tun.

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
