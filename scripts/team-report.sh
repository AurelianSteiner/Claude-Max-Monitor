#!/bin/bash
#
# Claude-Max-Auslastung melden
#
# Dieses Skript liest die eigene Claude-Nutzung aus und schreibt daraus eine
# kleine Meldedatei für die Team-Übersicht von Claude Max Monitor.
#
# WICHTIG: Der Session Key verlässt diesen Rechner nicht. Er geht ausschließlich
# an claude.ai, um die eigenen Zahlen abzufragen. In die Meldung kommen nur
# Prozentwerte, Reset-Zeitpunkte und der eigene Name — keine Zugangsdaten, keine
# Chats, keine Inhalte. Die Meldung wird vor dem Weitergeben angezeigt und kann
# in Ruhe durchgelesen werden.
#
# Verwendung:
#   bash team-report.sh
# und den Session Key sowie die Team-ID eingeben, wenn danach gefragt wird.
#
# Ohne Rückfragen (z. B. für einen wiederkehrenden Aufruf):
#   CLAUDE_SESSION_KEY=sk-ant-sid… \
#   CLAUDE_TEAM_ID=K7QP2M9X \
#   CLAUDE_TEAM_FOLDER="$HOME/Library/CloudStorage/Dropbox/Claude-Team" \
#   bash team-report.sh
#
#   CLAUDE_TEAM_ID      Team-ID aus der Anleitung (8 Zeichen). Fehlt sie, wird
#                       danach gefragt; bleibt sie leer, gibt es nur die
#                       lesbare Zusammenfassung und keine Meldedatei.
#   CLAUDE_TEAM_FOLDER  Der geteilte Ordner. Ist er gesetzt und beschreibbar,
#                       landet die Meldung direkt dort. Sonst wird sie auf dem
#                       Schreibtisch abgelegt und muss von Hand in den
#                       geteilten Ordner gezogen werden.
#   CLAUDE_REPORT_NAME  Anzeigename in der Übersicht (Vorgabe: Kontoname).
#
# Den Session Key findet man so:
#   1. claude.ai im Browser öffnen und anmelden
#   2. Entwicklerwerkzeuge öffnen (Cmd+Option+I)
#   3. Reiter „Application" (Chrome) bzw. „Speicher" (Firefox/Safari)
#   4. Cookies → https://claude.ai → Eintrag „sessionKey"
#   5. Den Wert kopieren (beginnt mit sk-ant-sid…)

set -u

BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; NC=$'\033[0m'

echo ""
echo "${BOLD}Claude-Max-Auslastung melden${NC}"
echo "${DIM}Der Session Key bleibt auf diesem Rechner. Weitergegeben werden nur Prozentzahlen.${NC}"
echo ""

# ------------------------------------------------------------------ Eingabe
if [ -n "${CLAUDE_SESSION_KEY:-}" ]; then
    SESSION_KEY="$CLAUDE_SESSION_KEY"
else
    printf "Session Key einfügen (Eingabe bleibt unsichtbar): "
    stty -echo 2>/dev/null
    read -r SESSION_KEY
    stty echo 2>/dev/null
    echo ""
fi

SESSION_KEY="$(printf '%s' "$SESSION_KEY" | tr -d '[:space:]')"
SESSION_KEY="${SESSION_KEY#sessionKey=}"

if [ -z "$SESSION_KEY" ]; then
    echo "${RED}Kein Session Key eingegeben. Abbruch.${NC}"; exit 1
fi

# ------------------------------------------------------------------ Team-ID
#
# Dasselbe Alphabet wie in der App (TeamConfig.idAlphabet): Großbuchstaben und
# Ziffern ohne I, O, 0 und 1 — die verwechselt man beim Vorlesen. Trennstriche
# und Leerzeichen dürfen drinstehen, sie fliegen hier raus. Ist am Ende nicht
# genau 8 Zeichen übrig, ist die Eingabe kaputt: dann lieber keine Meldedatei
# als eine, die im geteilten Ordner niemandem gehört.
normalize_team_id() {
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr -cd 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
}

if [ -n "${CLAUDE_TEAM_ID:-}" ]; then
    TEAM_ID_RAW="$CLAUDE_TEAM_ID"
else
    printf "Team-ID aus der Anleitung (leer lassen, wenn du keine hast): "
    read -r TEAM_ID_RAW || TEAM_ID_RAW=""
fi

TEAM_ID="$(normalize_team_id "${TEAM_ID_RAW:-}")"

if [ -n "${TEAM_ID_RAW:-}" ] && [ "${#TEAM_ID}" -ne 8 ]; then
    echo "${RED}Die Team-ID muss 8 Zeichen haben (Buchstaben und Ziffern, ohne I, O, 0 und 1).${NC}"
    echo "Ohne gültige ID gibt es gleich nur die lesbare Zusammenfassung."
    TEAM_ID=""
elif [ "${#TEAM_ID}" -ne 8 ]; then
    TEAM_ID=""
fi

UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

claude_get() {
    curl -sS --max-time 30 \
        -H "accept: */*" \
        -H "accept-language: de-DE,de;q=0.9,en;q=0.8" \
        -H "content-type: application/json" \
        -H "anthropic-client-platform: web_claude_ai" \
        -H "anthropic-client-version: 1.0.0" \
        -H "user-agent: $UA" \
        -H "origin: https://claude.ai" \
        -H "referer: https://claude.ai/settings/usage" \
        -H "sec-fetch-dest: empty" \
        -H "sec-fetch-mode: cors" \
        -H "sec-fetch-site: same-origin" \
        -H "Cookie: sessionKey=$SESSION_KEY" \
        "$1"
}

# ------------------------------------------------------------- Organisation
echo "Frage Organisation ab…"
ORGS="$(claude_get "https://claude.ai/api/organizations")"

if printf '%s' "$ORGS" | grep -qi "<html\|cloudflare\|just a moment"; then
    echo "${RED}Die Abfrage wurde vom Sicherheitssystem blockiert.${NC}"
    echo "Bitte claude.ai einmal im Browser öffnen, dann erneut versuchen."
    exit 1
fi

ORG_ID="$(printf '%s' "$ORGS" | python3 -c '
import json,sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if not isinstance(data, list) or not data:
    sys.exit(1)
# Bevorzugt die Organisation mit einem aktiven Abo, sonst die erste
for org in data:
    caps = org.get("capabilities") or []
    if any("claude_max" in str(c) or "claude_pro" in str(c) for c in caps):
        print(org.get("uuid", "")); break
else:
    print(data[0].get("uuid", ""))
' 2>/dev/null)"

if [ -z "$ORG_ID" ]; then
    echo "${RED}Organisation konnte nicht gelesen werden.${NC}"
    echo "Meist ist der Session Key abgelaufen — im Browser neu anmelden und den Wert erneut kopieren."
    exit 1
fi

# -------------------------------------------------------------- Nutzung
echo "Frage Nutzung ab…"
USAGE="$(claude_get "https://claude.ai/api/organizations/$ORG_ID/usage")"

WHO="${CLAUDE_REPORT_NAME:-$(id -F 2>/dev/null || whoami)}"

# ------------------------------------------------------- Meldung erzeugen
#
# Die Meldung entsteht als JSON — genau das Format, das die App liest
# (Usage4Claude/Models/TeamReport.swift): schema, teamId, person, reportedAt
# und limits[{label, percent, resetsAt}], Zeitstempel durchweg ISO 8601 in UTC
# mit „Z". Die lesbare Fassung weiter unten wird aus derselben JSON-Datei
# gerendert: Was auf dem Bildschirm steht, ist damit genau das, was auch
# weitergegeben wird.
#
# Team-ID und Name gehen über die Umgebung an Python, nicht über den Text des
# Programms — so kann kein Anführungszeichen im Namen das Skript zerlegen.
#
# Ausgegeben wird zuerst der Dateiname, danach die Meldung selbst. Das spart
# eine temporäre Datei für den Rückweg.
BUILT="$(printf '%s' "$USAGE" | TEAM_ID="$TEAM_ID" PERSON="$WHO" python3 -c '
import datetime, json, os, sys, unicodedata

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if not isinstance(d, dict):
    sys.exit(1)

def pct(block):
    """Prozentwert eines Limitblocks, 0…100 — oder None."""
    if not isinstance(block, dict):
        return None
    used = block.get("utilization")
    if used is None:
        used, total = block.get("used"), block.get("total")
        if used is None or not total:
            return None
        try:
            value = used / total * 100
        except Exception:
            return None
    else:
        value = used
    try:
        value = float(value)
    except Exception:
        return None
    if value != value or value in (float("inf"), float("-inf")):
        return None
    return max(0, min(100, int(round(value))))

def iso_z(raw):
    """Reset-Zeitpunkt als ISO 8601 in UTC, so wie die App ihn liest."""
    if not raw:
        return None
    try:
        t = datetime.datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
    except Exception:
        return None
    if t.tzinfo is None:
        t = t.replace(tzinfo=datetime.timezone.utc)
    return t.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def resets(block):
    if not isinstance(block, dict):
        return None
    return iso_z(block.get("resets_at") or block.get("resetsAt"))

def limit(label, block):
    value = pct(block)
    if value is None:
        return None
    entry = {"label": label[:40], "percent": value}
    at = resets(block)
    if at:
        entry["resetsAt"] = at
    return entry

limits = []
five = d.get("five_hour") or d.get("fiveHour")
seven = d.get("seven_day") or d.get("sevenDay")

for label, block in (("5 Stunden", five), ("7 Tage", seven)):
    entry = limit(label, block)
    if entry:
        limits.append(entry)

# Modellbezogene Limits sind Wochenfenster. Das Wort „7 Tage" muss in der
# Beschriftung stehen, sonst zählt die App sie nicht zu „fast am Limit"
# (siehe TeamSummary.weeklyMarkers).
for entry in (d.get("limits") or []):
    if not isinstance(entry, dict):
        continue
    name = (((entry.get("scope") or {}).get("model") or {}).get("display_name")) or "Modell"
    row = limit("%s 7 Tage" % name, entry)
    if row:
        limits.append(row)

if not limits:
    sys.exit(1)

def slug(person):
    """Wie TeamReport.slug in der App: a–z, 0–9 und Bindestrich."""
    text = person.lower()
    for a, b in (("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss"),
                 ("å", "a"), ("æ", "ae"), ("ø", "oe")):
        text = text.replace(a, b)
    text = "".join(c for c in unicodedata.normalize("NFD", text)
                   if not unicodedata.combining(c))
    out, pending = [], False
    for ch in text:
        if ch.isascii() and ch.isalnum():
            if pending and out:
                out.append("-")
            pending = False
            out.append(ch)
        elif out:
            pending = True
    return "".join(out)[:32].rstrip("-") or "person"

person = (os.environ.get("PERSON") or "").strip()[:60] or "Unbekannt"
team_id = (os.environ.get("TEAM_ID") or "").strip().upper()

report = {
    "schema": 1,
    "teamId": team_id,
    "person": person,
    "reportedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "limits": limits[:12],
}

sys.stdout.write("report-%s-%s.json\n" % (team_id, slug(person)))
sys.stdout.write(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
sys.stdout.write("\n")
')"

FILE_NAME="$(printf '%s\n' "$BUILT" | head -1)"
REPORT_JSON="$(printf '%s\n' "$BUILT" | tail -n +2)"

if [ -z "$REPORT_JSON" ]; then
    echo "${RED}Nutzungsdaten konnten nicht gelesen werden.${NC}"
    echo "Meist ist der Session Key abgelaufen — im Browser neu anmelden und den Wert erneut kopieren."
    exit 1
fi

# ------------------------------------------------------- Lesbare Fassung
READABLE="$(printf '%s' "$REPORT_JSON" | python3 -c '
import datetime, json, sys

r = json.load(sys.stdin)

def local(raw):
    if not raw:
        return "?"
    try:
        t = datetime.datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
    except Exception:
        return "?"
    return t.astimezone().strftime("%d.%m. %H:%M")

lines = ["Claude-Auslastung — %s (%s)" % (r["person"], local(r["reportedAt"]))]
for entry in r["limits"]:
    lines.append("%-18s: %3d%%  (frei ab %s)"
                 % (entry["label"], entry["percent"], local(entry.get("resetsAt"))))
print("\n".join(lines))
')"

echo ""
echo "${GREEN}Fertig. Das wird weitergegeben — mehr nicht:${NC}"
echo "${DIM}──────────────────────────────────────────${NC}"
echo "$READABLE"
echo "${DIM}──────────────────────────────────────────${NC}"

# ------------------------------------------------------------- Ablegen
#
# Ohne gültige Team-ID entsteht keine Datei: Eine Meldung ohne Team lehnt die
# App ohnehin ab, und im geteilten Ordner wäre sie nur Müll.
if [ -z "$TEAM_ID" ]; then
    echo ""
    echo "${DIM}Ohne Team-ID keine Meldedatei — die Zusammenfassung oben liegt in der Zwischenablage.${NC}"
    if command -v pbcopy >/dev/null 2>&1; then
        printf '%s' "$READABLE" | pbcopy
    fi
    echo ""
    exit 0
fi

[ -n "$FILE_NAME" ] || FILE_NAME="report-$TEAM_ID.json"

TARGET_DIR=""
if [ -n "${CLAUDE_TEAM_FOLDER:-}" ]; then
    if [ -d "$CLAUDE_TEAM_FOLDER" ] && [ -w "$CLAUDE_TEAM_FOLDER" ]; then
        TARGET_DIR="$CLAUDE_TEAM_FOLDER"
    else
        echo "${RED}CLAUDE_TEAM_FOLDER ist kein beschreibbarer Ordner:${NC} $CLAUDE_TEAM_FOLDER"
    fi
fi
if [ -z "$TARGET_DIR" ]; then
    if [ -d "$HOME/Desktop" ] && [ -w "$HOME/Desktop" ]; then
        TARGET_DIR="$HOME/Desktop"
    else
        TARGET_DIR="$PWD"
    fi
fi

TARGET="$TARGET_DIR/$FILE_NAME"

# Erst daneben schreiben, dann an Ort und Stelle schieben: Im geteilten Ordner
# liest womöglich gerade jemand mit, und `mv` innerhalb desselben Dateisystems
# ist unteilbar — eine halb geschriebene Meldung sieht so niemand.
TMP="$(mktemp "$TARGET_DIR/.team-report.XXXXXX" 2>/dev/null)"
if [ -n "$TMP" ] && printf '%s\n' "$REPORT_JSON" > "$TMP" 2>/dev/null && mv -f "$TMP" "$TARGET" 2>/dev/null; then
    chmod 644 "$TARGET" 2>/dev/null
    echo ""
    echo "${GREEN}Meldung gespeichert:${NC} $TARGET"
    if [ "${TARGET_DIR}" = "${CLAUDE_TEAM_FOLDER:-}" ]; then
        echo "${DIM}Liegt schon im geteilten Ordner — fertig.${NC}"
    else
        echo "${DIM}Diese Datei in den geteilten Ordner des Teams ziehen.${NC}"
    fi
else
    [ -n "$TMP" ] && rm -f "$TMP"
    echo ""
    echo "${RED}Die Meldung konnte nicht gespeichert werden.${NC} Ordner: $TARGET_DIR"
    echo "${DIM}Der Inhalt steht unten und liegt in der Zwischenablage.${NC}"
    echo "$REPORT_JSON"
fi

# In die Zwischenablage kommt die Meldung selbst: Genau diesen Text nimmt die
# App unter „Team → Meldung einfügen" entgegen, wenn der Ordner nicht erreichbar
# ist und man sie stattdessen per Nachricht schickt.
if command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$REPORT_JSON" | pbcopy
    echo "${DIM}(Die Meldung liegt außerdem in der Zwischenablage — falls du sie lieber verschickst.)${NC}"
fi
echo ""
