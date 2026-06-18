# MacZones

**Leichtgewichtiges Fenster-Zonen-Snapping für macOS.**

MacZones ist eine bewusst minimale Alternative zu Tools wie
[MacsyZones](https://github.com/rohanrhu/MacsyZones). Es kann genau eine Sache –
Fenster in selbst definierte Zonen einrasten – und tut das mit **nahezu 0 % CPU
im Leerlauf**.

## Warum?

Viele Window-Manager laufen mit dauerhaft hoher CPU-Last (Polling, Analyse,
Hintergrund-Tasks). MacZones hat **keine Timer und kein Polling**. Die gesamte
Laufzeit-Aktivität hängt an einem einzigen passiven `CGEventTap`, der **nur dann
feuert, wenn tatsächlich eine Maustaste gedrückt ist** (Down / Up / Drag).
Bewegt man die Maus ohne gedrückte Taste, bekommt MacZones gar kein Event. Im
Ruhezustand entstehen also keine Wakeups und keine messbare CPU-Last.

## Funktionen (und nur die)

- **Rechtsklick-Ziehen** – rechte Maustaste über einem Fenster gedrückt halten
  und ziehen. Das Fenster folgt dem Mauszeiger, die Zonen erscheinen; beim
  Loslassen über einer Zone rastet das Fenster ein. (Ein normaler Rechtsklick
  ohne Ziehen öffnet wie gewohnt das Kontextmenü.)
- **Einrasten beim Wackeln** – ein Fenster normal ziehen und kurz hin- und
  herwackeln. Die Zonen erscheinen, beim Loslassen über einer Zone rastet das
  Fenster ein.
- **Mehrere Zonen zusammenfassen** – beim Ziehen über mehrere benachbarte Zonen
  spannt das Fenster über deren gemeinsamen Bereich.
- **Zonen-Editor pro Bildschirm** – Zonen aufziehen, verschieben, in der Größe
  ändern und löschen. Öffnen per Menü oder Shortcut **⌃⌥Z**.
- **Auto-Raster** – einen Bildschirm automatisch in *n* Spalten × *m* Zeilen
  unterteilen (mit optionaler Lücke), entweder im Editor oder direkt über das
  Menü „Schnelles Raster".
- **Profile** – verschiedene Zonen-Layouts speichern und umschalten; pro
  Bildschirm getrennt.
- **Menüleisten-Symbol** mit allen Optionen, optional „Bei Anmeldung starten".

Bewusst **nicht** enthalten: Statistiken/Analyse, Hintergrund-Daemons,
Cloud-Sync, Tastatur-Kacheln, Animationen-Overkill – nichts, was im Leerlauf
Leistung zieht.

## Installation

### Fertige Version (empfohlen)

1. Unter [Releases](../../releases) die aktuelle `MacZones.dmg` (oder `.zip`)
   herunterladen.
2. `MacZones.app` in den Ordner **Programme** ziehen.
3. Da die App nicht über Apple notarisiert ist, einmalig die
   Gatekeeper-Quarantäne entfernen:
   ```bash
   xattr -dr com.apple.quarantine /Applications/MacZones.app
   ```
4. MacZones ganz normal aus **Programme** öffnen (Doppelklick). Es erscheint
   **kein Dock-Symbol** – MacZones ist ein Menüleisten-Tool und zeigt sein
   Symbol oben rechts in der Menüleiste. Über dieses Symbol erreichst du alle
   Einstellungen (Profile, Raster, Berechtigung, Bei Anmeldung starten …).
   Öffnest du die App erneut aus „Programme", während sie schon läuft, klappt
   automatisch ihr Menü auf.
5. Beim ersten Start nach der **Bedienungshilfen**-Berechtigung fragen lassen
   (siehe unten). Die Berechtigung kannst du jederzeit auch über das
   Menüleisten-Menü erteilen.

### Selbst bauen

Voraussetzung: macOS 13+, Xcode / Swift 5.9+.

```bash
git clone https://github.com/ProjectMakersDE/MacZones.git
cd MacZones
./scripts/build-app.sh
open dist
```

Das Skript erzeugt ein universelles (Apple Silicon + Intel) `MacZones.app`
inklusive `.zip` und `.dmg` unter `dist/`.

#### Lokal installieren (mit stabiler Signatur)

Damit lokale Builds dieselbe Signatur-Identität wie die Releases haben (und die
Bedienungshilfen-Berechtigung erhalten bleibt), einmalig die lokale Signier-
Identität einrichten, danach jederzeit bauen + nach `/Applications` installieren:

```bash
./scripts/setup-local-signing.sh        # einmalig: Zertifikat + lokale Keychain (+ CI-Secrets)
./scripts/install-local.sh 0.4.1        # baut signiert und installiert nach /Applications
```

`setup-local-signing.sh` legt eine dedizierte Signier-Keychain an
(`~/Library/Keychains/maczones-signing.keychain-db`) und hinterlegt dasselbe
Zertifikat als GitHub-Secrets, sodass CI-Releases und lokale Builds identisch
signiert sind.

## Berechtigung

MacZones benötigt **Bedienungshilfen** (Accessibility), um Fenster anderer Apps zu
bewegen und Mausgesten zu erkennen:

> Systemeinstellungen › Datenschutz & Sicherheit › **Bedienungshilfen** →
> MacZones aktivieren.

Kein Neustart nötig – sobald die Berechtigung erteilt ist, funktioniert MacZones
sofort.

**Berechtigung bleibt über Updates erhalten:** Die Release-Builds werden mit
einem **stabilen, selbstsignierten Zertifikat** signiert (gleiche Identität bei
jedem Build). macOS bindet die Bedienungshilfen-Freigabe an diese Identität –
deshalb muss sie nur **einmal** erteilt werden und bleibt bei künftigen Updates
bestehen. (Beim Wechsel von einer alten ad-hoc-signierten Version den alten
„MacZones"-Eintrag einmal entfernen (−) und neu hinzufügen.)

## Updates

MacZones aktualisiert sich über GitHub-Releases:

- Menü → **„Auf Updates prüfen …"** lädt das neueste Release, installiert es und
  startet MacZones neu (die Berechtigung bleibt dank gleichem Zertifikat
  erhalten).
- **„Beim Start nach Updates suchen"** (Standard: an) macht beim Start *einen*
  stillen Check; ist eine neuere Version verfügbar, erscheint im Menü ein
  Hinweis. Kein Hintergrund-Polling.
- Die installierte Version steht oben im Menü und unter **„Über MacZones"**.

### Signatur-Zertifikat (für Maintainer)

Das Signatur-Zertifikat wird einmalig erzeugt und als GitHub-Secrets hinterlegt:

```bash
./scripts/create-signing-cert.sh ProjectMakersDE/MacZones
```

Das setzt die Secrets `SIGNING_CERTIFICATE_P12_BASE64` und
`SIGNING_CERTIFICATE_PASSWORD`. Der Build-Workflow importiert sie und signiert
damit. Ohne diese Secrets fällt der Build automatisch auf Ad-hoc-Signatur zurück.

## Bedienung in Kürze

| Aktion | So geht's |
| --- | --- |
| Zonen bearbeiten | Menü → „Zonen bearbeiten" oder **⌃⌥Z** |
| Zone teilen | im Editor **in eine Zone klicken** (teilt an der Stelle); **⌥** = horizontal |
| Mit einer Zone starten | Palette → „Auf eine Zone zurücksetzen", dann teilen |
| Auto-Raster | Palette → Schnellauswahl oder Spalten/Zeilen frei eingeben (bis 64 × 32) |
| Fenster einrasten (Rechtsklick) | Rechte Maustaste über Fenster halten → ziehen → über Zone loslassen |
| Fenster einrasten (Wackeln) | Fenster ziehen → kurz wackeln → über Zone loslassen |
| Mehrere Zonen | beim Ziehen über benachbarte Zonen streichen |
| Schnelles Raster | Menü → „Schnelles Raster" (gilt für den Bildschirm unter der Maus) |
| Profil wechseln | Menü → „Profil" |

## Architektur

| Datei | Zweck |
| --- | --- |
| `EventTapController.swift` | Der eine `CGEventTap`; verarbeitet beide Gesten, swallowt Rechtsklick-Drags, ist im Leerlauf inaktiv. |
| `ShakeDetector.swift` | Erkennt das Wackeln aus Drag-Positionen (reine Arithmetik). |
| `SnapSession.swift` | Zonen-Overlays + Zielberechnung während einer Geste. |
| `ZoneEditorController.swift` | Editor-Fenster + Palette, Auto-Raster, Profile. |
| `AX.swift` | Accessibility: Fenster finden / bewegen / skalieren. |
| `ScreenManager.swift` | Koordinaten-Umrechnung Cocoa ↔ Quartz, pro Bildschirm. |
| `ProfileStore.swift` | Profile + Einstellungen als JSON in Application Support. |
| `StatusBarController.swift` | Menüleisten-Menü. |

## Lizenz

MIT – siehe [LICENSE](LICENSE).
