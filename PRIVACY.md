# Datenschutz / Privacy

> **TODO vor der ersten Veröffentlichung / before the first release:** Verantwortlicher und Kontakt / controller and contact: `TODO`. Speicherdauer in PostHog / retention in PostHog: `TODO`.

## Deutsch

**Lokal:** Notizen, Todos, Projekte, Sessions, Zeiterfassung und das Nutzungsprotokoll liegen nur auf deinem Mac in `~/Library/Application Support/FocusFlow/`.

**Freiwillige Nutzungsdaten:** Nur wenn du zustimmst, sendet FocusFlow Daten an PostHog (EU). Ohne Antwort oder mit „Nein“ wird nichts gesammelt und nichts gesendet. Die Daten sind pseudonym: Sie hängen an einer zufälligen ID, die nichts mit dir oder dem lokalen Protokoll zu tun hat.

- Mit jedem Ereignis: zufällige ID, zufällige Sitzungs-ID, Zeitpunkt (auf die Minute), App-Version, macOS-Version (z. B. 15.7), Prozessortyp, Sprache der App
- Timer: Start, Ende, Pause, Dauer, Runde, ob abgeschlossen
- Bedienung: geöffnete Bereiche, genutzte Wege (z. B. Menü oder Tastenkürzel)
- Todos und Projekte: dass etwas angelegt, geändert oder erledigt wurde, Anzahlen, geschätzte Minuten, Länge einer Notiz in Zeichen, Nummer der Projektfarbe
- Einstellungen: Name der geänderten Einstellung, nur Zahlen und An/Aus als Werte
- Blockieren und Zeiterfassung: dass etwas geblockt oder zugeordnet wurde, Anzahlen, Minuten
- KI: Anbieter, Erfolg, Dauer
- Abstürze: Fehlernummern, Build-Nummer, Positionen im Code von FocusFlow und einigen bekannten Systembibliotheken

Nie gesendet werden Notizen, Titel, Projektnamen, App-Namen, Webseiten, Fenstertitel, Dateipfade, Modellnamen und Fehlertexte. Die vollständige Liste steht im Code: [`RemoteContract`](Sources/FocusFlow/RemoteTelemetry.swift).

**Zweck und Rechtsgrundlage:** Verbesserung und Stabilität der App; deine Einwilligung (Art. 6 Abs. 1 lit. a DSGVO). **Empfänger:** PostHog, EU-Region. Beim Senden wird technisch bedingt deine IP-Adresse übertragen; das PostHog-Projekt soll sie verwerfen, und die Ortsbestimmung ist abgeschaltet.

**Widerruf und Löschung:** Einstellungen → Allgemein, jederzeit. Noch nicht Gesendetes wird dabei gelöscht. Für die Löschung gesendeter Daten nenne dem Kontakt oben deine ID aus den Einstellungen. „Neue ID“ trennt künftige von bisherigen Daten; notiere die alte vorher.

**Updates:** Die Suche nach Updates und das Laden laufen über GitHub. GitHub sieht dabei deine IP-Adresse. Ein Systemprofil wird nicht mitgeschickt. Die automatische Suche lässt sich abschalten.

## English

**Local:** Notes, tasks, projects, sessions, time tracking and the usage log stay on your Mac in `~/Library/Application Support/FocusFlow/`.

**Voluntary usage data:** FocusFlow sends data to PostHog (EU) only if you agree. Without an answer, or with “No”, nothing is collected for sending and nothing is sent. The data is pseudonymous: it is tied to a random ID unrelated to you or to the local log.

- With every event: random ID, random session ID, time (to the minute), app version, macOS version (e.g. 15.7), processor type, app language
- Timer: start, end, pause, length, round, whether completed
- Use: opened areas, how you got there (e.g. menu or shortcut)
- Tasks and projects: that something was created, changed or completed, counts, estimated minutes, length of a note in characters, number of the project color
- Settings: name of the changed setting, only numbers and on/off as values
- Blocking and time tracking: that something was blocked or assigned, counts, minutes
- AI: provider, success, duration
- Crashes: error numbers, build number, code positions in FocusFlow and some well-known system libraries

Never sent: notes, titles, project names, app names, websites, window titles, file paths, model names and error texts. The complete list is in the code: [`RemoteContract`](Sources/FocusFlow/RemoteTelemetry.swift).

**Purpose and legal basis:** improving the app and its stability; your consent (Art. 6(1)(a) GDPR). **Recipient:** PostHog, EU region. Sending technically transmits your IP address; the PostHog project is meant to discard it, and location lookup is off.

**Withdrawal and deletion:** Settings → General, at any time. Anything not sent yet is deleted. To have sent data deleted, give the contact above your ID from the settings. “New ID” separates future from past data; note the old one first.

**Updates:** Checking for and downloading updates uses GitHub, which sees your IP address. No system profile is sent. Automatic checks can be turned off.
