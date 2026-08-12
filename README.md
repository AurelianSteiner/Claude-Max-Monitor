# Claude Max Monitor

Alle Claude-Max-Konten auf einen Blick in der Menüleiste — statt eines nach dem anderen.

## Download

**[Neueste Version herunterladen](https://github.com/AurelianSteiner/Claude-Max-Monitor/releases/latest)** — DMG öffnen, App nach „Programme" ziehen.

Beim ersten Start Rechtsklick auf die App → **Öffnen**. Die App ist nicht bei Apple notarisiert, deshalb fragt macOS einmal nach. Danach startet sie normal.

Ab dann meldet sie sich selbst, wenn eine neue Version erscheint.

## Worum es geht

Wer mehrere Claude-Max-Zugänge hat, kennt das Problem: du willst wissen, mit welchem Konto du weiterarbeiten kannst, und musst dafür zwischen ihnen durchklicken. Vier Konten heißt vier Klicks, und am Ende hast du die erste Zahl schon wieder vergessen.

Diese App zeigt alle Konten gleichzeitig, eine Karte pro Zugang:

**Das Wochenlimit als Leitzahl.** Groß, farbig, sofort lesbar. Daran hängt die Planung — nicht am Sitzungsfenster, das sich alle fünf Stunden von selbst erledigt.

**Das Sitzungsfenster als Wasserstand.** Ein Kreis, der sich füllt. Die Prozentzahl darin wird an der Wasserlinie zweifarbig, bleibt also in jedem Füllstand lesbar.

**Farbe sagt, wie eng es wird.** Blau, wenn Luft ist. Gelb, orange, rot, je näher das Limit rückt. Ein Blick über alle Karten genügt.

**Countdown, wenn es knapp wird.** Freischaltung in unter drei Tagen zeigt die Restzeit, alles darüber das Datum. Der genaue Tag steht im Tooltip.

**Weitere Limits nach Bedarf.** Opus, Fable, Extra Usage — je nachdem, was dich interessiert, ein- und ausschaltbar in den Anzeigeoptionen.

Ein Klick auf eine Karte macht das Konto zum aktiven, dem das Symbol in der Menüleiste folgt. Optional zeigt die App auch ChatGPT-/Codex-Kontingente in derselben Übersicht.

Die Zugangsdaten bleiben im Schlüsselbund des Macs. Es gibt keinen Server, keine Telemetrie, keine Konten bei Dritten — die App spricht ausschließlich mit den Schnittstellen, bei denen du dich angemeldet hast.

## Selbst bauen

Xcode ist nicht nötig, die Command Line Tools reichen:

```bash
./scripts/build_without_xcode.sh
```

Eigene Version veröffentlichen:

```bash
./scripts/release.sh 1.1 "Was neu ist"
```

Das baut, packt die DMG, signiert sie, schreibt `appcast.xml` fort und legt das GitHub-Release an.

## Herkunft

Fork von [Usage4Claude](https://github.com/f-is-h/Usage4Claude) von f-is-h, MIT-Lizenz. Die Mehrkonten-Übersicht, die Wasserstand-Anzeige und der Build ohne Xcode sind in diesem Fork entstanden.

Lizenz: MIT — siehe [LICENSE](LICENSE).
