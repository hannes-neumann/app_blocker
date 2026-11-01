# FocusFlow

Eine macOS-Menüleisten-App, die einen Pomodoro-Fokustimer mit App- und Webseiten-Blocker kombiniert
und spontane Gedanken während der Fokuszeit in konkrete Todos verwandelt, die dir in der nächsten
passenden Pause vorgeschlagen werden.

## Features

- **Pomodoro-Timer** in der Menüleiste: Fokus, kurze und lange Pausen, Runden, Pause/Überspringen/Stopp.
- **App-Blocker**: Ausgewählte Apps werden während der Fokuszeit beendet und beim erneuten Öffnen sofort wieder geschlossen.
- **Webseiten-Blocker**: Domains werden systemweit über `/etc/hosts` gesperrt (gilt für alle Browser).
- **Schnellnotiz** mit `⌃⌥N`: ein schwebendes Textfeld, egal in welcher App du gerade bist. Mit Enter speichern, mit Esc schließen.
- **Timer-Shortcut** mit `⌃⌥T`: öffnet ein Eingabefenster für eine eigene Fokusdauer. Mit Enter oder einer Vorauswahl startet der Timer direkt.
- **KI-Aufbereitung**: Ein Sprachmodell auf deinem Mac (Apple Foundation Model oder ein Ollama-Modell) macht aus der Notiz ein oder mehrere konkrete Todos mit geschätzter Dauer.
- **Pausenvorschlag**: Zu Beginn jeder Pause schlägt FocusFlow das längste offene Todo vor, das noch in die Pause passt.
- **Dashboard**: ein eigenes Fenster mit Timer, allen Todos (Titel bearbeiten, Dauer anpassen, erledigen, löschen), Statistik und Einstellungen. Öffnest du es über „Dashboard“ im Menü.
- **Projekte und Aufgaben**: Projekte mit konkreten Aufgaben anlegen, pro Projekt oder Aufgabe eigene App-Sperrlisten hinterlegen und vor dem Fokus die Aufgabe auswählen. Regeln der Aufgabe überschreiben Projektregeln, ansonsten wird die globale Regel verwendet.
- **Statistik**: Fokuszeit pro Tag mit Tagesziel, Serie, durchgezogene Sessions, erledigte Todos, Fokuszeit nach Tageszeit und Fokuszeit pro Aufgabe, für 7 oder 30 Tage. Im Menü steht eine Kurzübersicht für heute.

## Bauen und starten

Es reichen die Xcode Command Line Tools (Swift 6 und das macOS 26 SDK), Xcode selbst wird nicht gebraucht.

```bash
./scripts/build-app.sh
```

```bash
open build/FocusFlow.app
```

Für die Entwicklung reicht auch `swift build`. Das fertige `.app`-Bundle braucht es für Menüleiste und Tastenkürzel.

## Wie es funktioniert

| Teil | Umsetzung |
| --- | --- |
| Timer & Zustand | `AppState.swift` |
| App-Blocker | `AppBlocker.swift` beobachtet über `NSWorkspace` App-Starts und -Aktivierungen |
| Webseiten-Blocker | `DomainBlocker.swift` (siehe unten) |
| Tastenkürzel | `HotKey.swift` über die Carbon Hot-Key-API (braucht keine Bedienungshilfen-Freigabe) |
| Todos & Vorschlag | `TodoStore.swift` |
| Statistik | `StatsStore.swift`, `Views/StatsView.swift` (Swift Charts) |
| Dashboard | `Views/DashboardView.swift` |
| KI | `AIEngine.swift` (Auswahl des Modells), `OllamaClient.swift`, `TodoRefiner.swift` (Anweisungen, Stichwort-Schätzung) |
| Protokoll | `Analytics.swift` (Events, `AnalyticsSink`, lokale Datei) |

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

FocusFlow startet Ollama beim Öffnen und beendet es beim Schließen wieder, außer es lief schon vorher (abschaltbar
unter Einstellungen → KI). Das Modell (Standard `gemma3:4b`, etwa 3 GB) lädst du danach in den Einstellungen per „Modell laden“. Läuft
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

## Bekannte Grenzen

- Bereits geöffnete Tabs gesperrter Seiten können bis zum Neuladen weiterlaufen, weil Browser bestehende Verbindungen und DNS-Antworten kurz zwischenspeichern.
- Die Tastenkürzel sind im Moment fest auf `⌃⌥N` (Schnellnotiz) und `⌃⌥T` (Timer) eingestellt.
- Apps mit ungesicherten Dokumenten fragen beim Beenden nach. Lehnst du ab, wird die App nur ausgeblendet.
