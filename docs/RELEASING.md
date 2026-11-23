# FocusFlow veröffentlichen

## Einmalige Einrichtung

1. Erstelle ein PostHog-Konto, wähle die EU-Region und aktiviere **Discard client IP data**. Kopiere nur den
   Project Key (keine persönliche URL und kein API-Secret).
2. Installiere Swift 6, die Xcode Command Line Tools und die Sparkle-Artefakte (`swift build`).
3. Erstelle unter **Settings → Environments** die Umgebung `release`, füge dich als erforderlichen Reviewer hinzu und
   erlaube nur Tags nach `v*`. Das muss vor dem Setup-Skript passieren, weil es die Secrets dort ablegt.
4. Prüfe, dass `gh auth status` auf das öffentliche Repository zeigt, und führe als Eigentümer
   `scripts/setup-release.sh` aus. Wähle ein Verzeichnis außerhalb des Repositorys für die Backups.
5. Bestätige die Zertifikats- und Sparkle-Schritte einzeln. Das Skript erzeugt ein zehn Jahre gültiges
   selbstsigniertes Zertifikat, prüft dessen p12-Import in einem temporären Schlüsselbund und verwendet
   das Sparkle-Konto `focusflow-release` für EdDSA.
6. Prüfe danach die Environment-Secrets: Zertifikat plus Passwort und Sparkle Public plus Private Key müssen jeweils
   gemeinsam gesetzt sein. Der Release-Workflow verlangt auch den PostHog-Key.
7. Trage in `PRIVACY.md` Kontakt und Speicherdauer ein.

Bewahre p12, Passwort und Sparkle-Private-Key offline auf; bei Verlust des Zertifikats müssen Nutzer die
App wegen einer neuen Signatur neu installieren. Bei Verlust des Sparkle-Schlüssels muss die
Update-Vertrauenskette neu eingerichtet werden. Eine Zertifikatsrotation sollte deshalb erst nach
vollständiger Sicherung des alten Zertifikats erfolgen.

Die kostenlose Infrastruktur besteht aus GitHub Releases und Actions (für öffentliche Repositories) sowie
PostHogs kostenloser EU-Stufe. Ein GitHub Student Pack ist dafür nicht nötig und wird hier nicht als aktuelles
Angebot versprochen. Ohne kostenpflichtiges Apple-Entwicklerprogramm gibt es keine Notarisierung; Apples
Gebührenerlass gilt nicht für Einzelpersonen. Beim ersten Start wählen Nutzer deshalb „Dennoch öffnen“ unter
Systemeinstellungen → Datenschutz & Sicherheit. Spätere Sparkle-Updates werden mit EdDSA verifiziert.

## Dry Run

Starte die Action unter **Actions → Release → Run workflow** mit einer bestehenden `X.Y.Z`-Version.
Sie läuft mit Ad-hoc-Signatur ohne Secrets und lädt DMG und ZIP als Workflow-Artefakte hoch; sie erstellt
keinen Release und veröffentlicht nichts. Prüfe die Artefakte lokal, bevor du einen annotierten Tag auf
`main` erstellst.

## Jede Veröffentlichung

1. Ergänze einen Abschnitt `## X.Y.Z` in `CHANGELOG.md` und erhöhe die Version in `Resources/Info.plist`.
2. Führe lokal `scripts/test.sh` und `FOCUSFLOW_SIGN_IDENTITY=- scripts/release.sh` aus.
3. Erstelle und pushe einen **annotierten** Tag `vX.Y.Z` auf `main`.
4. Die konfigurierte `release`-Environment-Freigabe durch den erforderlichen Reviewer wird nur für `v*`-Tags
   wirksam. Nach dieser Freigabe baut die Action, erstellt einen Draft mit DMG, ZIP und Appcast, lädt alles hoch und
   veröffentlicht denselben Draft unmittelbar danach. Eine manuelle Prüfung zwischen Draft und Veröffentlichung
   findet nicht statt; prüfe daher Changelog und Dry Run vorher.
5. Nutzer sehen beim ersten Start „Open Anyway“; spätere Updates werden von Sparkle anhand der EdDSA-Signatur
   geprüft und installiert.

Pseudonyme Telemetrie verwendet eine zufällige, zurücksetzbare ID, ist opt-in und standardmäßig aus. In
PostHog sind Aktivierung, Retention nach Version, abgeschlossene Fokus-Sessions und Abstürze nützliche
Fragen. Aktivierung lässt sich nach `app_version` und Installationsereignis, Retention nach erster Session,
Fokusabschluss nach Session-Ende sowie Abstürze nach Version und macOS-Version aufschlüsseln. Die Crash-
Auswertung steht in PostHog unter **Data → Insights** (und in **Error tracking**, falls aktiviert); sie
enthält nur die von der App gesendeten pseudonymen Ereignisse. Personenbezogene Inhalte gehören nicht in
Events; siehe [PRIVACY.md](../PRIVACY.md).

## Schlüsselverlust und Rollback

Veröffentliche nie einen älteren Build erneut. Behebe das Problem und veröffentliche eine höhere Version;
Sparkle kann so die fehlerhafte Version überholen. Bei Verlust des Zertifikats oder privaten Sparkle-Schlüssels
stoppe Releases, sichere die verbleibenden Backups und plane die nötige Neuinstallation beziehungsweise
Schlüsselrotation ausdrücklich, statt Secrets halb zu ersetzen.
