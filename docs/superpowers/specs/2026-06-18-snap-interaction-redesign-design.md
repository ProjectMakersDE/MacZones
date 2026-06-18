# Snap-Interaktion: Redesign + Bugfix

Datum: 2026-06-18
Status: Genehmigt (Design), bereit für Implementierungsplan

## Problem

Das Snappen von Fenstern in Zonen ist unbrauchbar:

1. **Falsches Fenster wird gesnappt (Hauptbug).** Beim Wackeln wird das zu snappende
   Fenster an `lmbDownLocation` gegriffen — dem Punkt, an dem die linke Maustaste
   *ursprünglich* gedrückt wurde. Bis der Nutzer wackelt, hat macOS das gezogene
   Fenster aber längst mitbewegt; an der alten Stelle liegt nun ein *anderes*
   Fenster (oder der Desktop). MacZones snappt daher beim Loslassen ein fremdes
   Fenster → „zieht random andere Fenster irgendwo hin".

2. **Rechte Maustaste löst nichts aus.** Der aktuelle „Rechtsklick-Ziehen"-Modus
   ist ein eigener Modus (nur rechte Taste halten und ziehen). Hält der Nutzer
   links gedrückt und drückt rechts dazu, liefert macOS keine `rightMouseDragged`
   mehr — der Modus kommt nie über `pending` hinaus. Das gewünschte Verhalten
   (rechts als *Modifier* beim Linksziehen) existiert im Code nicht.

3. **Mehrfachauswahl nicht rücknehmbar.** Ist der Anker einmal gesetzt, gibt es
   keinen Weg, die Zonen-Auswahl ohne Snap wieder zu verwerfen.

## Zielbild (Bedienmodell)

Ein einziger „Snap-Versuch"-Zustand, ausgelöst während eines normalen
**Linksdrag** eines Fensters.

### Zonen einblenden / ausblenden (Toggle)
- **Wackeln** schaltet die Zonen an bzw. (erneut) wieder aus.
- **Rechte Maustaste kurz tippen** (< ~250 ms) schaltet die Zonen an bzw. aus.

### Auswahl, solange Zonen sichtbar sind
- **Standard (rechte Taste nicht gehalten):** nur **eine** Zone ist ausgewählt —
  die, über der das Fenster gerade schwebt. Folgt dem Cursor.
- **Rechte Taste gedrückt halten:** **Mehrfachauswahl**. Anker = Zone beim Drücken;
  Auswahl = Bounding-Box von Anker bis aktuelle Zone. Zurückziehen verkleinert.
- **Rechte Taste loslassen nach echtem Sweep:** die Mehrfachauswahl wird
  **eingefroren** und bleibt als Auswahl bestehen, unabhängig von weiterer
  Cursorbewegung.
  - „Echter Sweep" = während des Haltens wurde mindestens eine andere Zone als der
    Anker berührt. Hat sich nichts ausgedehnt, kehrt die Auswahl auf
    Einzelzone-Folgen zurück (das Halten war wirkungslos).

### Snappen
- **Linke Taste loslassen:**
  - Auswahl vorhanden (einzeln oder eingefroren) → Fenster snappt dorthin.
  - Zonen sichtbar, aber keine Zone unter Cursor → kein Snap, Zonen verschwinden.
  - Zonen ausgeblendet → normaler Drag, kein Snap.

### Eingefrorene Auswahl ändern
- Kurz tippen / wackeln (Zonen aus), dann neu beginnen.

### Außerhalb eines Fenster-Drags
- Rechtsklicks bleiben unangetastet (Kontextmenü normal). Es werden nur
  Right-Down/Up/Dragged **während eines aktiven Linksdrags** geschluckt.

## Tippen-vs-Halten-Erkennung

Beim `rightMouseUp` (passend zu einem geschluckten `rightMouseDown` während
Linksdrag):

- **Tippen** = Druckdauer < ~250 ms **und** kein Sweep (keine Zonenausdehnung).
  - Zonen waren vor dem Druck **aus** → bleiben **an** (Einblenden bestätigt).
  - Zonen waren vor dem Druck **an** → werden **aus** (verwerfen).
- **Halten** = sonst. Mehrfachauswahl wird beendet → bei echtem Sweep eingefroren,
  sonst zurück auf Einzelzone.

## Architektur / Änderungen

### `EventTapController.swift`
- **Entfernen:** kompletter Rechtsklick-Drag-Modus — `RMBState`, `rmb`,
  `rmbDownLocation`, `grabWindow`, `grabOffset`, `moveGrabWindow(_:)`,
  `resynthesizeRightClick(at:)`.
- **Linker Drag treibt alles.** `onLeftDragged` ist die einzige kontinuierliche
  Quelle für Highlight-Updates (weil bei gehaltener linker Taste keine
  `rightMouseDragged` kommen).
- **Neuer Zustand** (ersetzt `shakeActive`/`shakeWindow`):
  - `snapArmed: Bool` — Zonen sichtbar.
  - `snapWindow: AXUIElement?` — das zu snappende Fenster.
  - `rightHeld: Bool` — rechte Taste aktuell gedrückt (→ Mehrfachauswahl).
  - `rightDownTime: TimeInterval` — für Tippen-vs-Halten.
  - `rightRevealedThisPress: Bool` — ob dieser Druck die Zonen eingeblendet hat.
  - `swallowRightUp: Bool` — den zu einem geschluckten Down gehörenden Up schlucken.
- **`onRightDown`** (nur wenn Linksdrag aktiv, sonst Event durchlassen):
  - Zonen aus → einblenden (Fenster an aktueller Cursor-Position greifen),
    `rightRevealedThisPress = true`; sonst `false`.
  - Greift kein Fenster (nichts Snappbares unter Cursor) und Zonen waren aus →
    nicht einblenden, Event trotzdem schlucken.
  - `rightHeld = true`, `rightDownTime = now`, Anker fixieren (Multi-Modus an).
  - Event schlucken (kein Kontextmenü), `swallowRightUp = true`.
- **`onRightUp`** (passend geschluckt): `rightHeld = false`; Tippen-vs-Halten
  auswerten (s. o.); Event schlucken.
- **`onLeftDown`/`onLeftDragged`/`onLeftUp`:**
  - `onLeftDragged`: Shake-Detector immer füttern (Toggle per Wackeln, auch wenn
    Zonen schon an). Sind Zonen sichtbar → `SnapSession.update(loc, multi: rightHeld)`.
  - **Bugfix:** Fenster beim Einblenden an **aktueller** `loc` greifen, nicht an
    `lmbDownLocation`.
  - `onLeftUp`: bei `snapArmed` → `SnapSession.end()`-Ziel auf `snapWindow`
    anwenden (async, damit der App-eigene Drag zuerst abschließt). Zustand
    zurücksetzen.

### `SnapSession.swift`
- `update(globalPoint:)` → `update(globalPoint:multi:)`:
  - `frozen` → nichts tun (Auswahl bleibt).
  - `multi == true` → Anker fix, Union Anker→Treffer (bisheriges Verhalten);
    `didExpand` setzen, sobald Treffer ≠ Anker.
  - `multi == false` → Anker = Treffer (Einzelzone folgt dem Cursor).
- `beginMulti()` — Multi-Modus an, `didExpand = false`, Anker beim nächsten Update.
- `endMulti()` — Multi-Modus aus; bei `didExpand` → `frozen = true`, sonst
  Einzelzone-Folgen.
- `setRevealed`/Toggle-Hilfen nach Bedarf; `cancel()` (ohne Snap) bleibt.
- Beim Toggle-Aus / `end()` / `cancel()` alle Flags zurücksetzen
  (`frozen`, `multi`, `didExpand`, Anker).

### `ProfileStore.swift`
- Persistierte Keys `rightClickDragEnabled` / `shakeEnabled` bleiben (Kompat).
  Bedeutung: `rightClickDragEnabled` = „rechte Taste schaltet/erweitert Zonen",
  `shakeEnabled` = „Wackeln schaltet Zonen". UI-Beschriftung ggf. anpassen.

### `StatusBarController.swift` (falls Beschriftungen)
- Menü-/Settings-Texte an die neue Bedeutung anpassen (kein „Rechtsklick-Ziehen"
  mehr, sondern „Rechte Taste: Zonen ein/aus + Mehrfachauswahl").

## Offene Annahme (beim Testen verifizieren)
- macOS liefert bei gehaltener **linker** Taste trotzdem `rightMouseDown` /
  `rightMouseUp` an den Session-Event-Tap. Üblich, aber zu bestätigen. Falls
  nicht: zusätzlich `otherMouseDown`/`otherMouseUp` (Button-Nummer prüfen)
  behandeln.

## Tests / Verifikation
- Kein Unit-Test-Target vorhanden; AX-/Event-Tap-Verhalten ist nur im echten
  System prüfbar. Verifikation manuell:
  1. Fenster links ziehen, weit ziehen, dann wackeln → **dieses** Fenster snappt
     (kein fremdes).
  2. Während Linksdrag rechte Taste kurz tippen → Zonen an; nochmal → aus.
  3. Rechte Taste halten + über mehrere Zonen ziehen → Bounding-Box; loslassen →
     eingefroren; links loslassen → Snap in kombinierte Fläche.
  4. Rechtsklick ohne Fenster-Drag → Kontextmenü normal.
