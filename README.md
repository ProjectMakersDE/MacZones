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

## Berechtigung

MacZones benötigt **Bedienungshilfen** (Accessibility), um Fenster anderer Apps zu
bewegen und Mausgesten zu erkennen:

> Systemeinstellungen › Datenschutz & Sicherheit › **Bedienungshilfen** →
> MacZones aktivieren.

Kein Neustart nötig – sobald die Berechtigung erteilt ist, funktioniert MacZones
sofort.

## Bedienung in Kürze

| Aktion | So geht's |
| --- | --- |
| Zonen bearbeiten | Menü → „Zonen bearbeiten" oder **⌃⌥Z** |
| Zone teilen | im Editor **in eine Zone klicken** (teilt an der Stelle); **⌥** = horizontal |
| Mit einer Zone starten | Palette → „Auf eine Zone zurücksetzen", dann teilen |
| Auto-Raster | Palette → Schnellauswahl (2×2 … 6×6) oder Spalten/Zeilen einstellen |
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
