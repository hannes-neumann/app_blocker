# FocusFlow veröffentlichen

## Einmalige Einrichtung

1. Erstelle ein PostHog-Konto, wähle die EU-Region und aktiviere **Discard client IP data**. Kopiere den
   Project Key (keine persönliche URL oder API-Secret).
2. Installiere Swift 6 und die Sparkle-Artefakte (`swift build` genügt).
3. Führe als Repository-Eigentümer `scripts/setup-release.sh` aus. Das Skript fragt vor jedem externen Schritt,
   erzeugt ein zehn Jahre gültiges selbstsigniertes Zertifikat und Sparkle-EdDSA-Schlüssel und speichert die
   GitHub-Secrets über `gh secret set`. Sichere `.p12` und den privaten Sparkle-Schlüssel offline: Bei Verlust
   müssen Nutzer die App neu installieren beziehungsweise verlieren die Update-Vertrauenskette.

Die kostenlose Infrastruktur besteht aus GitHub Releases und Actions (für öffentliche Repositories) sowie
PostHogs kostenloser EU-Stufe. Ohne kostenpflichtiges Apple-Entwicklerprogramm gibt es keine Notarisierung;
Apples Gebührenerlass gilt nicht für Einzelpersonen. Der erste Start braucht deshalb „Dennoch öffnen“ unter
Systemeinstellungen → Datenschutz & Sicherheit. Danach prüft Sparkle Updates mit EdDSA.

## Jede Veröffentlichung

1. Aktualisiere `CHANGELOG.md` und erhöhe die Version in `Resources/Info.plist`.
2. Prüfe `scripts/test.sh` und `scripts/build-app.sh`.
3. Erstelle und pushe den Tag `vX.Y.Z` auf `main`.
4. Prüfe den Draft-Release, seine DMG/ZIP und `appcast.xml`; erst danach veröffentlicht die Action ihn.

Telemetrie ist opt-in und standardmäßig aus. In PostHog sind Aktivierung, Retention nach Version,
abgeschlossene Fokus-Sessions und Abstürze nützliche Fragen. Personenbezogene Inhalte gehören nicht in
Events; siehe [PRIVACY.md](../PRIVACY.md).

## Rollback

Veröffentliche nie einen älteren Build erneut. Behebe das Problem und veröffentliche eine höhere Version;
Sparkle kann so die fehlerhafte Version überholen. Bei einem fehlerhaften Draft lösche ihn vor der Veröffentlichung.
