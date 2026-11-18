# FocusFlow

Eine macOS-Menüleisten-App, die einen Pomodoro-Fokustimer mit App- und Webseiten-Blocker kombiniert
und spontane Gedanken während der Fokuszeit in konkrete Todos verwandelt, die dir in der nächsten
passenden Pause vorgeschlagen werden.

Alles läuft auf deinem Mac. Kein Konto, keine Cloud und keine Bildschirmaufnahme; die App sammelt keine
Bildschirmpixel. Für die Zuordnung liest sie ausschließlich sichtbaren Text über die macOS-Bedienungshilfen
und speichert diesen gelesenen Text nicht.

## Features

- **Pomodoro-Timer** in der Menüleiste: Fokus, kurze und lange Pausen, Runden, Pause/Überspringen/Stopp.
- **Ausschlusslisten**: Ausgewählte Apps werden während der Fokuszeit beendet und beim erneuten Öffnen sofort wieder geschlossen. Für Websites sperrst du Domains systemweit über `/etc/hosts` (für alle Browser).
- **Projekte und Aufgaben überschreiben die App-Liste**: Eine eigene App-Liste eines Projekts oder einer Aufgabe ersetzt die globale App-Liste während dieser Zielauswahl.
- **Passwortgeschützte Webseiten-Sperre**: Für die Installation des kleinen Systemdienstes fragt macOS einmalig nach dem Admin-Passwort. Die Sperre gilt nur, solange FocusFlow läuft und eine Fokus-Session aktiv ist; beim Beenden oder Absturz verschwindet sie.
- **Schnellnotiz** mit `⌃⌥N`: ein schwebendes Textfeld, egal in welcher App du gerade bist. Mit Enter speichern, mit Esc schließen.
- **Timer-Shortcut** mit `⌃⌥T`: öffnet ein Eingabefenster für eine eigene Fokusdauer. Mit ↑↓ wählst du Projekt oder Aufgabe, mit ⇥ suchst du danach, mit Enter startet der Timer.
- **KI-Aufbereitung**: Ein Sprachmodell auf deinem Mac (Apple Foundation Model oder ein Ollama-Modell) macht aus der Notiz ein oder mehrere konkrete Todos mit geschätzter Dauer.
- **Pausenvorschlag**: Zu Beginn jeder Pause schlägt FocusFlow das längste offene Todo vor, das noch in die Pause passt.
- **Dashboard**: ein eigenes Fenster mit Übersicht (Timer mit Projektwahl, Tagesziel, Wochenzahlen, Wochendiagramm nach Projekt, Insights, heutige Sessions, nächste Todos), Projekten, Todos, Insights und Einstellungen. Öffnest du es über „Dashboard“ im Menü.
- **Projekte**: Projekte mit Farbe, Symbol und optionalem Wochenziel anlegen (Seitenleiste, Übersicht oder Menü). Vor dem Start wählst du ein Projekt und optional eine Aufgabe, die Session zählt dann für dieses Projekt. Sessions lassen sich nachträglich umhängen, z. B. in der Pause oder in der Session-Liste. Jede Projektseite zeigt Fokuszeit, Verlauf, Tageszeiten, Aufgaben mit Fokuszeit gegen Schätzung und eigene App-Sperrlisten. Projekte lassen sich über das …-Menü auf der Projektseite abschließen und wieder öffnen. Abgeschlossene Projekte behalten Verlauf und Statistik, erscheinen in der Übersicht unter „Abgeschlossene Projekte“ und nicht mehr in Auswahlmenüs (Timer, Todos, Zuordnung). Die automatische Erfassung ordnet ihnen keine Zeit mehr zu und Claude (MCP) sieht sie nicht mehr. Offene Todos bleiben unverändert. Regeln der Aufgabe überschreiben Projektregeln, ansonsten gilt die globale Regel.
- **Automatische Zeiterfassung** (optional, auch außerhalb von Fokus-Sessions): erfasst die vordere App, das daneben sichtbare Fenster, Fenstertitel und Browser-Adressen und ordnet die Zeit außerhalb von Fokus-Sessions über Regeln den Projekten zu. Während einer Fokus-Session zählt die erfasste Zeit für das gewählte Projekt. Projekt-Namen im sichtbaren Accessibility-Text können ebenfalls einem Projekt zugeordnet werden – aber nur bei einem eindeutigen Treffer; bei mehrdeutigem Text bleibt die Aktivität ohne Projekt. Keine Bildschirmaufnahme, alles bleibt lokal.
- **Text-Datenschutz**: Es wird kein Bildschirm aufgenommen und es werden keine Bildpunkte gesammelt. Passwortfelder (`AXSecureTextField`) werden nie gelesen; ausgeschlossene Apps werden vollständig übersprungen. Standardmäßig gehört dazu eine Ausschlussliste mit Passwort-Managern und privaten Nachrichten-Apps wie 1Password, Bitwarden, Schlüsselbundverwaltung, WhatsApp, Signal, Telegram, Discord und Nachrichten. Die Liste lässt sich in den Einstellungen bearbeiten. Gelesener Text wird nur für den Projekt-Abgleich verwendet und nicht gespeichert.
- **Claude-Anbindung (MCP)**: Claude kann deine Todos und Projekte lesen, sie mit deinem Kalender zu Fokus-Blöcken einplanen und Todos anlegen, abhaken oder starten. Siehe unten.
- **Insights**: Fokuszeit pro Tag nach Projekt mit Tagesziel, Trend zum Zeitraum davor, Zeit nach Projekt, Tageszeiten, Wochentage, Schätzgenauigkeit, Fokuszeit pro Aufgabe und alle Sessions, für 7, 30 oder 90 Tage, dazu automatisch formulierte Auffälligkeiten. Im Menü steht eine Kurzübersicht für heute.

## Bauen und starten

Es reichen die Xcode Command Line Tools (Swift 6 und das macOS 26 SDK), Xcode selbst wird nicht gebraucht.

```bash
./scripts/build-app.sh
```

```bash
open build/FocusFlow.app
```

Für die Entwicklung reicht auch `swift build`. Das fertige `.app`-Bundle braucht es für Menüleiste und Tastenkürzel.

Schneller geht es mit dem Befehl `focusflow`, der von jedem Ordner aus baut und neu startet. Einmal einrichten:

```bash
ln -s "$PWD/scripts/focusflow" ~/.local/bin/focusflow
```

Danach baut `focusflow` die App und startet sie neu. Weitere Befehle: `focusflow build`, `start`, `stop`, `test` und
`release`. Eine laufende Fokus-Session wird nur mit `--force` beendet. `focusflow help` zeigt alles.

## Tests

```bash
./scripts/test.sh
```

Die Tests (Swift Testing, in `Tests/FocusFlowTests`) prüfen die Logik, die beim Umbauen leicht verloren geht: Dauern
parsen, Notizen schätzen, Übersetzungen (jeder Text auf Deutsch und Englisch mit denselben Platzhaltern), Regeln der
Zeiterfassung, die KI-Warteschlange, Todos inklusive Bearbeiten während der Aufbereitung, das Laden alter Dateien und
den MCP-Server, der dafür wie bei Claude als eigener Prozess läuft. Sie arbeiten in einem eigenen Ordner
(`FOCUSFLOW_DATA_DIR`) und fassen deine echten Daten nicht an.

Auf GitHub laufen sie bei jedem Push und Pull Request (`.github/workflows/tests.yml`). Lokal vor jedem Push, wenn du
den Hook einmal einschaltest:

```bash
git config core.hooksPath .githooks
```

## Weitergeben

Ohne Apples kostenpflichtiges Entwicklerprogramm lässt sich FocusFlow mit einem eigenen Zertifikat signieren. Weil die
Signatur dann bei jedem Build gleich bleibt, behält macOS die erteilten Berechtigungen (Bedienungshilfen, Automation)
auch nach Updates.

Einmalig das Zertifikat anlegen: **Schlüsselbundverwaltung → Menü Schlüsselbundverwaltung → Zertifikatsassistent →
Zertifikat erstellen…**, Name `FocusFlow Developer`, Identitätstyp „Selbstsigniertes Stammzertifikat“,
Zertifikatstyp „Codesignatur“. Danach:

```bash
./scripts/release.sh
```

Das baut die App für Apple-Chips und Intel und legt `FocusFlow-<Version>.dmg` und `.zip` in `build/release`. Beim
ersten Signieren fragt macOS, ob `codesign` den Schlüssel benutzen darf („Immer erlauben“). Die Version steht in
`Resources/Info.plist` (`CFBundleShortVersionString`). Erhöhe sie vor jeder neuen Weitergabe. Ein anderes Zertifikat
wählst du mit `FOCUSFLOW_SIGN_IDENTITY="Name" ./scripts/release.sh`.

Die App ist nicht von Apple notarisiert. Beim ersten Start muss sie deshalb einmal unter Systemeinstellungen →
Datenschutz & Sicherheit mit „Dennoch öffnen“ freigegeben werden. Die DMG enthält dazu eine kurze Anleitung
(`Resources/INSTALL.txt`).

## Wie es funktioniert

| Teil | Umsetzung |
| --- | --- |
| Timer & Zustand | `AppState.swift` |
| App-Blocker | `AppBlocker.swift` beobachtet über `NSWorkspace` App-Starts und -Aktivierungen |
| Webseiten-Blocker | `DomainBlocker.swift` (siehe unten) |
| Tastenkürzel | `HotKey.swift` über die Carbon Hot-Key-API (braucht keine Bedienungshilfen-Freigabe) |
| Todos & Vorschlag | `TodoStore.swift` |
| Insights | `StatsStore.swift`, `Insights.swift` (Auswertungen), `Views/StatsView.swift` (Swift Charts) |
| Dashboard | `Views/DashboardView.swift`, `Views/ProjectsView.swift`, `Views/DashboardComponents.swift`, `ProjectStyle.swift` (Projektfarben) |
| Sprachen | `Localization.swift` (alle Texte auf Deutsch und Englisch) |
| KI | `AIEngine.swift` (Auswahl des Modells), `AIBatchQueue.swift` (wann das Modell läuft), `OllamaClient.swift`, `TodoRefiner.swift` (Anweisungen, Stichwort-Schätzung) |
| Protokoll | `Analytics.swift` (Events, `AnalyticsSink`, lokale Datei) |
| Zeiterfassung | `ActivityTracker.swift`, `Views/TrackingViews.swift` |
| Claude (MCP) | `Sources/FocusFlowMCP/main.swift`, Links `focusflow://` in `AppState.open(_:)` |

**Webseiten-Sperre:** Beim ersten Fokus installiert FocusFlow einmalig einen kleinen Systemdienst
(`/Library/LaunchDaemons/com.hannesneumann.FocusFlow.blocker.plist`). Dafür fragt macOS ein einziges Mal
nach dem Admin-Passwort, danach nie wieder. Der Dienst liest zwei Dateien der App (`block-state` und
`blocked-domains`) und schreibt nur, solange der Status „on“ ist *und* FocusFlow läuft, einen markierten
Block in `/etc/hosts`. Beendest du die App oder stürzt sie ab, verschwindet die Sperre innerhalb von
Sekunden, und beim Systemstart räumt der Dienst Reste auf. Er akzeptiert nur reguläre Dateien deines
Benutzers und nur gültige Domainnamen. Entfernen kannst du ihn unter Einstellungen → Blockieren.

**KI:** Unter Einstellungen → KI wählst du das Modell. „Automatisch“ nimmt Apple Intelligence
(erst ab **macOS 26** mit aktivierter Apple Intelligence) und sonst **Ollama**, das offene Modelle lokal
ausführt. Ollama installierst du einmal mit:

```bash
brew install ollama
```

FocusFlow startet Ollama nur, wenn Notizen aufbereitet werden, und beendet es danach sofort wieder, außer es lief schon
vorher (abschaltbar unter Einstellungen → KI). Notizen laufen gesammelt als Batch: In einer Fokus-Session warten sie bis
kurz vor der Pause, außerhalb etwa eine Minute. Bis dahin steht eine grobe Schätzung am Todo. Das Modell wird direkt nach
jedem Batch aus dem Speicher entfernt. Das Modell (Standard `gemma3:4b`, etwa 3 GB) lädst du danach in den Einstellungen per „Modell laden“. Läuft
keins von beiden, übernimmt FocusFlow die Notiz direkt als Todo und schätzt die Dauer anhand von Stichworten.
Eine Angabe wie „30 min“ oder „2h“ in der Notiz wird immer als Dauer übernommen. Die geschätzte Dauer lässt
sich per Klick auf das Zeit-Badge ändern, entweder über eine Vorauswahl oder mit „Eigene Dauer eingeben…“
als Text („25“, „45 min“, „1h“, „1,5h“, „1:30“).

Daten (Einstellungen, Projekte, Todos und Fokus-Sessions) liegen in `~/Library/Application Support/FocusFlow/`.

**Protokoll:** Jede Bedienung wird als eine JSON-Zeile in `Logs/events-JJJJ-MM-TT.jsonl` im selben Ordner
gespeichert (abschaltbar und löschbar unter Einstellungen → Allgemein, Dateien älter als 180 Tage werden
gelöscht). Jedes Event hat `name`, `timestamp`, `sessionID` (ein App-Start), `installID`, `appVersion`,
`properties` und optional `content`. In `content` stehen persönliche Texte wie Notizen, Todo-Titel und Domains;
alles andere ist frei von Inhalten. Auswerten lässt es sich z. B. so:

```bash
cat ~/Library/Application\ Support/FocusFlow/Logs/*.jsonl | jq -s 'group_by(.name) | map({name: .[0].name, count: length})'
```

Event-Namen und Schlüssel folgen den Regeln von Firebase Analytics (snake_case, höchstens 40 Zeichen). Für ein
späteres Backend implementiert man `AnalyticsSink`, lässt dabei `content` weg, fragt die Nutzer vorher um
Erlaubnis und hängt den Sink an `Analytics.sinks` an.

## Claude-Anbindung (MCP)

`scripts/build-app.sh` legt den MCP-Server `focusflow-mcp` in die App (`FocusFlow.app/Contents/MacOS/focusflow-mcp`). Unter Einstellungen → Allgemein → Claude kopierst du die passende Konfiguration:

- **Claude Desktop**: den Eintrag unter `mcpServers` in `~/Library/Application Support/Claude/claude_desktop_config.json` einfügen und Claude neu starten.
- **Claude Code**: den kopierten Befehl `claude mcp add --scope user focusflow -- …` im Terminal ausführen.

Werkzeuge:

| Werkzeug | Was es tut |
| --- | --- |
| `get_planning_context` | offene Todos mit einzuplanender Zeit, Projekte mit Wochenziel, Pomodoro-Einstellungen, Schätzfaktor, beste Fokuszeiten |
| `list_todos` | Todos, optional nach Projekt oder mit erledigten |
| `plan_focus_blocks` | verteilt Todos auf freie Zeitfenster: nach Projekt gebündelt, in Pomodoros mit Pausen, lange Todos aufgeteilt. Liefert Titel, Beschreibung und einen Start-Link für jeden Kalendertermin. Legt selbst nichts an. |
| `add_todo`, `complete_todo`, `start_focus` | ändern Todos oder starten eine Session über die laufende App |

So planst du mit Claude: „Plan mir meine FocusFlow-Todos morgen in den Kalender.“ Claude liest den Kontext, holt die Termine aus dem Google-Kalender, rechnet die freien Zeiten aus, lässt `plan_focus_blocks` verteilen, zeigt dir den Plan und legt die Termine erst nach deinem OK an. Der Link im Termin (`focusflow://focus?task=…`) startet den Fokus direkt in FocusFlow.

Der Server liest die Dateien der App nur. Änderungen schickt er über `focusflow://`-Links an die laufende App, damit sie die einzige Stelle bleibt, die schreibt. Links, die Daten ändern, brauchen das Token aus `mcp-token` im Datenordner, das nur dein Benutzer lesen kann. Ein Fokus-Link geht ohne Token.

## Bekannte Grenzen

- Bereits geöffnete Tabs gesperrter Seiten können bis zum Neuladen weiterlaufen, weil Browser bestehende Verbindungen und DNS-Antworten kurz zwischenspeichern.
- Die Tastenkürzel sind im Moment fest auf `⌃⌥N` (Schnellnotiz) und `⌃⌥T` (Timer) eingestellt.
- Apps mit ungesicherten Dokumenten fragen beim Beenden nach. Lehnst du ab, wird die App nur ausgeblendet.
