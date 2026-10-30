# FocusFlow

Eine macOS-Menüleisten-App, die einen Pomodoro-Fokustimer mit App- und Webseiten-Blocker kombiniert
und spontane Gedanken während der Fokuszeit in konkrete Todos verwandelt, die dir in der nächsten
passenden Pause vorgeschlagen werden.

## Features

- **Pomodoro-Timer** in der Menüleiste: Fokus, kurze und lange Pausen, Runden, Pause/Überspringen/Stopp.
- **App-Blocker**: Ausgewählte Apps werden während der Fokuszeit beendet und beim erneuten Öffnen sofort wieder geschlossen.
- **Webseiten-Blocker**: Domains werden systemweit über `/etc/hosts` gesperrt (gilt für alle Browser).
- **Schnellnotiz** mit `⌃⌥N`: ein schwebendes Textfeld, egal in welcher App du gerade bist. Mit Enter speichern, mit Esc schließen.
- **KI-Aufbereitung**: Das Apple Foundation Model (on-device) macht aus der Notiz ein oder mehrere konkrete Todos mit geschätzter Dauer.
- **Pausenvorschlag**: Zu Beginn jeder Pause schlägt FocusFlow das längste offene Todo vor, das noch in die Pause passt.
- **Statistik**: Fokuszeit pro Tag mit Tagesziel, Serie, durchgezogene Sessions, erledigte Todos und Fokuszeit nach Tageszeit, für 7 oder 30 Tage. Im Menü steht eine Kurzübersicht für heute.

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
| KI | `TodoRefiner.swift` |

**Webseiten-Sperre:** Beim ersten Fokus installiert FocusFlow einmalig einen kleinen Systemdienst
(`/Library/LaunchDaemons/com.hannesneumann.FocusFlow.blocker.plist`). Dafür fragt macOS ein einziges Mal
nach dem Admin-Passwort, danach nie wieder. Der Dienst liest zwei Dateien der App (`block-state` und
`blocked-domains`) und schreibt nur, solange der Status „on“ ist *und* FocusFlow läuft, einen markierten
Block in `/etc/hosts`. Beendest du die App oder stürzt sie ab, verschwindet die Sperre innerhalb von
Sekunden, und beim Systemstart räumt der Dienst Reste auf. Er akzeptiert nur reguläre Dateien deines
Benutzers und nur gültige Domainnamen. Entfernen kannst du ihn unter Einstellungen → Blockieren.

**KI:** Das Foundation Model gibt es erst ab **macOS 26 mit aktivierter Apple Intelligence**. Auf
älteren Systemen oder ohne Apple Intelligence übernimmt FocusFlow die Notiz direkt als Todo und
schätzt die Dauer anhand von Stichworten. Eine Angabe wie „30 min“ oder „2h“ in der Notiz wird immer
als Dauer übernommen. Die geschätzte Dauer lässt sich im Menü per Klick auf das Zeit-Badge ändern.

Daten (Einstellungen, Todos) liegen in `~/Library/Application Support/FocusFlow/`.

## Bekannte Grenzen

- Bereits geöffnete Tabs gesperrter Seiten können bis zum Neuladen weiterlaufen, weil Browser bestehende Verbindungen und DNS-Antworten kurz zwischenspeichern.
- Das Tastenkürzel ist im Moment fest auf `⌃⌥N` eingestellt.
- Apps mit ungesicherten Dokumenten fragen beim Beenden nach. Lehnst du ab, wird die App nur ausgeblendet.
