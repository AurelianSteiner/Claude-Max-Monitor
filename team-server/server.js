//
// Claude Max Monitor — Team-Relay
//
// Winziger Dienst ohne Abhängigkeiten: Kolleginnen und Kollegen schicken ihre
// Auslastungs-Prozente (POST), die App des Admins holt sie ab (GET). Es werden
// ausschließlich Prozentwerte, Labels und Reset-Zeitpunkte gespeichert —
// niemals Session Keys, Chats oder andere Inhalte.
//
// Umgebungsvariablen:
//   TEAM_TOKENS Teams und ihre Geheimnisse: "TEAMID1:token1,TEAMID2:token2".
//               Jede Anfrage braucht "Authorization: Bearer <token des Teams>".
//               Neue Teams = neuen Eintrag ergänzen, Railway startet neu, fertig.
//   TEAM_TOKEN  Abkürzung für genau ein Team (Team-ID egal) — für den Start.
//   DATA_DIR    Ablage (Railway-Volume), Standard /data
//   PORT        von Railway gesetzt
//
// Endpunkte:
//   GET  /health                     Lebenszeichen, ohne Token
//   POST /v1/reports                 eine Meldung speichern (JSON, max 64 KB)
//   GET  /v1/teams/:teamId/reports   alle Meldungen eines Teams
//

const http = require("http");
const fs = require("fs");
const path = require("path");

const PORT = Number(process.env.PORT) || 8080;
const DATA_DIR = process.env.DATA_DIR || "/data";
const MAX_BODY_BYTES = 64 * 1024;
const ID_PATTERN = /^[A-Z0-9]{4,16}$/; // Team-IDs wie "K7QP2M9X"

// Team-ID -> Token. Leerer Schlüssel "" = Token gilt für jedes Team (TEAM_TOKEN-Abkürzung).
const teamTokens = new Map();
for (const pair of String(process.env.TEAM_TOKENS || "").split(",")) {
  const idx = pair.indexOf(":");
  if (idx > 0) teamTokens.set(pair.slice(0, idx).trim().toUpperCase(), pair.slice(idx + 1).trim());
}
if (process.env.TEAM_TOKEN) teamTokens.set("", process.env.TEAM_TOKEN.trim());

if (teamTokens.size === 0) {
  console.error("Weder TEAM_TOKENS noch TEAM_TOKEN gesetzt — Start verweigert.");
  process.exit(1);
}

fs.mkdirSync(DATA_DIR, { recursive: true });

function send(res, status, body) {
  const data = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(data),
    "cache-control": "no-store",
  });
  res.end(data);
}

const crypto = require("crypto");

function tokenMatches(candidate, expected) {
  if (!expected || candidate.length !== expected.length) return false;
  // Zeitkonstanter Vergleich, damit das Token nicht über Antwortzeiten erratbar ist
  return crypto.timingSafeEqual(Buffer.from(candidate), Buffer.from(expected));
}

/// Prüft das Bearer-Token gegen das Team — oder gegen das Allzweck-Token ("").
function authorized(req, teamId) {
  const header = req.headers["authorization"] || "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (!token) return false;
  if (tokenMatches(token, teamTokens.get(String(teamId || "").toUpperCase()))) return true;
  return tokenMatches(token, teamTokens.get(""));
}

/// Dateiname aus dem Personennamen: nur [a-z0-9-], damit nichts aus DATA_DIR ausbricht
function slug(value) {
  return String(value)
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40) || "anonym";
}

function validReport(report) {
  if (typeof report !== "object" || report === null) return "kein Objekt";
  if (!ID_PATTERN.test(String(report.teamId || ""))) return "teamId fehlt oder ungültig";
  if (typeof report.person !== "string" || !report.person.trim()) return "person fehlt";
  if (!Array.isArray(report.limits) || report.limits.length === 0) return "limits fehlen";
  for (const limit of report.limits) {
    if (typeof limit !== "object" || limit === null) return "limit ist kein Objekt";
    if (typeof limit.label !== "string") return "limit.label fehlt";
    const percent = Number(limit.percent);
    if (!Number.isFinite(percent) || percent < 0 || percent > 1000) return "limit.percent ungültig";
  }
  return null;
}

function readBody(req, callback) {
  let size = 0;
  const chunks = [];
  req.on("data", (chunk) => {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) {
      req.destroy();
      callback(new Error("zu groß"), null);
      return;
    }
    chunks.push(chunk);
  });
  req.on("end", () => callback(null, Buffer.concat(chunks).toString("utf8")));
  req.on("error", (error) => callback(error, null));
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://localhost");

  if (req.method === "GET" && url.pathname === "/health") {
    return send(res, 200, { ok: true });
  }

  // POST /v1/reports — eine Meldung speichern.
  // Das Token wird gegen die Team-ID AUS der Meldung geprüft, daher erst lesen.
  if (req.method === "POST" && url.pathname === "/v1/reports") {
    return readBody(req, (error, raw) => {
      if (error) return send(res, 413, { error: "Meldung zu groß" });
      let report;
      try {
        report = JSON.parse(raw);
      } catch {
        return send(res, 400, { error: "kein gültiges JSON" });
      }
      const problem = validReport(report);
      if (problem) return send(res, 400, { error: problem });
      if (!authorized(req, report.teamId)) {
        return send(res, 401, { error: "Token fehlt oder passt nicht zum Team" });
      }

      report.receivedAt = new Date().toISOString();
      if (!report.reportedAt) report.reportedAt = report.receivedAt;

      const teamDir = path.join(DATA_DIR, String(report.teamId));
      const file = path.join(teamDir, `${slug(report.person)}.json`);
      try {
        fs.mkdirSync(teamDir, { recursive: true });
        fs.writeFileSync(file, JSON.stringify(report));
      } catch (writeError) {
        console.error("Schreiben fehlgeschlagen:", writeError.message);
        return send(res, 500, { error: "Speichern fehlgeschlagen" });
      }
      return send(res, 200, { ok: true, stored: path.basename(file) });
    });
  }

  // GET /v1/teams/:teamId/reports — alle Meldungen eines Teams
  const match = url.pathname.match(/^\/v1\/teams\/([A-Z0-9]{4,16})\/reports$/);
  if (req.method === "GET" && match) {
    if (!authorized(req, match[1])) {
      return send(res, 401, { error: "Token fehlt oder passt nicht zum Team" });
    }
    const teamDir = path.join(DATA_DIR, match[1]);
    let reports = [];
    try {
      const entries = fs.existsSync(teamDir) ? fs.readdirSync(teamDir) : [];
      for (const entry of entries) {
        if (!entry.endsWith(".json")) continue;
        try {
          const raw = fs.readFileSync(path.join(teamDir, entry), "utf8");
          if (raw.length > MAX_BODY_BYTES) continue;
          reports.push(JSON.parse(raw));
        } catch {
          // Eine kaputte Datei darf die anderen nicht blockieren
        }
      }
    } catch (readError) {
      console.error("Lesen fehlgeschlagen:", readError.message);
      return send(res, 500, { error: "Lesen fehlgeschlagen" });
    }
    reports.sort((a, b) => String(b.reportedAt || "").localeCompare(String(a.reportedAt || "")));
    return send(res, 200, { reports });
  }

  return send(res, 404, { error: "unbekannter Pfad" });
});

server.listen(PORT, () => {
  console.log(`Team-Relay läuft auf Port ${PORT}, Ablage: ${DATA_DIR}`);
});
