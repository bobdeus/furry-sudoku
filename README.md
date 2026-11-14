# Furry Sudoku

A standalone Godot 4.7.2 cat logic game for Android and Windows. Everything runs locally: puzzle generation, hints, settings, and saved progress. There are no advertisements, accounts, analytics, network calls, music, sounds, or online dependencies. The Android manifest requests only vibration permission.

## Play

Download the APK or Windows executable from [GitHub Releases](https://github.com/bobdeus/furry-sudoku/releases/latest). This repository is private, so sign in to the GitHub account with access before downloading.

- Windows: run `builds/windows/Furry Sudoku.exe`. The game is embedded in this single executable.
- Android: install `builds/android/Furry Sudoku.apk`. It is a release-signed APK for Android 7.0 or later, supporting ARM64 phones and x86_64 devices.
- Levels continue indefinitely, with no return to level 1. Every ten completed puzzles adds a completed round to your saved totals. Every tenth level is super hard; levels ending in 5 are hard.
- Each puzzle starts with three fresh hearts, except levels 7, 17, 27, and so on: those are one-heart challenges. Running out of hearts lets you retry the same puzzle with fresh hearts and an empty board, keeping your level and completion totals.
- One cat belongs in every row, column, and colored region. Cats must not touch, including diagonally.

Tap to toggle an X. Drag to mark or clear several squares. Double-tap to place a cat. The middle button switches between marking and single-tap cat placement. On Windows, right-click places a cat; arrow keys move the cursor, Space or X marks, Enter places, H requests a hint, Z undoes notes, and Escape goes back.

Hints are unlimited. The first tap highlights the simplest available clue. A second tap explains it and outlines the affected squares. A third applies that deduction. Incorrect notes are corrected before the engine reasons from them. Undo affects notes; it never refunds mistakes. Vibration and automatic exclusion marks are adjustable in Settings.

Progress is saved after each move and on pause/exit. On Windows, the save is in `%APPDATA%/Godot/app_userdata/Furry Sudoku/progress.json`. Android uses the app's private local storage. There is no cross-device sync. Version 1.1 upgrades existing saves, keeping the current puzzle and solved totals and using total completed puzzles for continuous level numbering. An unfinished puzzle gets its new heart allowance; a puzzle already out of hearts remains ready to retry.

### Install on Android

1. Open the release page in your phone's browser and download the `.apk` under **Assets**. Alternatively, connect the phone to your PC with a USB cable, choose **File transfer** on the phone, and copy the local APK into the phone's **Download** folder.
2. Open the APK from Downloads or your phone's Files app.
3. If Android requests permission, tap **Settings** and enable **Allow from this source** for the browser or Files app you used. Return to the APK and tap **Install**.
4. Tap **Open** to play. You can turn off **Allow from this source** afterward; the installed game keeps working offline.

Menu names vary by phone. Google's guides cover [USB file transfer](https://support.google.com/android/answer/9064445?hl=en) and [installing apps from other sources](https://support.google.com/pixelphone/answer/7391672?hl=en).

## Generation and difficulty

`scripts/puzzle_engine.gd` builds connected colored regions around a legal cat arrangement. An exact solver counts solutions, stopping after two; only a fully proved unique puzzle is accepted. Competing solutions are removed by changing region boundaries while preserving connectivity and the intended solution.

Harder puzzles also use three locally bundled, generated seed layouts. These are starting points for boundary mutations, rotations/reflections, and color permutations, with fresh layouts also sampled. Every resulting puzzle has its uniqueness and difficulty checked again. The seeds avoid a long search when a phone reaches a difficult level; this is not a fixed list of playable levels.

Difficulty follows the hint engine's actual deductions:

1. Direct exclusions and a single remaining position.
2. Overlapping constraints and cells ruled out by every candidate in a unit.
3. Reserved pairs/triples across rows, columns, and regions — required for hard boards.
4. Hypothetical placement leading to a contradiction, with exact search as a deeper fallback — required for super hard boards.

The hint ranking is this game's implementation of the described behavior, rather than a verified reproduction of Oakever's internal algorithm.

## Develop and build

Open `project.godot` in Godot 4.7.2 (standard edition; GDScript). Press F6/F5 or run Godot with `--path` pointing here. The optional user argument `--play` opens the current puzzle directly.

Run `powershell -ExecutionPolicy Bypass -File tools/build.ps1` to export both targets. Parameters `-Godot`, `-JavaHome`, and `-Target Windows|Android|All` allow different local installations. Install matching Godot export templates and configure the Android SDK and JDK paths in Godot's editor settings. Android needs SDK platform/build tools compatible with the installed export template.

The first Android build creates `.signing/furry-sudoku.keystore` and `.signing/android.json`. **Keep both files backed up privately:** they are needed to sign future APK updates for the same installation. They are excluded from exports and version control. Never replace them to rebuild an existing release.

The generation CLI can export a puzzle and an optional fully explained solve:

```powershell
godot --headless --path . --script res://tools/generate.gd -- super 12345 C:/path/to/puzzle.json 1000 explain
```

Arguments are difficulty (`easy`, `hard`, `super`), numeric seed, output file, maximum candidate attempts, and optional `explain`. Put temporary output outside the project.

## Assets and credits

The visual reference was Meowdoku by Oakever Games: a warm cream canvas, colored rounded tiles, white X marks, cat faces, rule cards, and soft circular controls. This project uses its own name, code, mascot, and icons.

- `assets/cat.png`: original mascot generated using the built-in image-generation tool. Prompt: “Use case: stylized-concept. Asset type: a single polished game sprite for a cozy cat logic puzzle called Furry Sudoku. Draw one original adorable tuxedo kitten HEAD ONLY, front facing, with charcoal black fur, large pointed ears with dusky pink inner ears, fluffy white cheeks and chin, white blaze from forehead down to tiny coral pink nose, luminous friendly hazel-green eyes, fine white whiskers and a soft contented smile. Premium softly shaded 3D cartoon mobile-game illustration, rounded plush forms, delicate fur texture, warm soft studio light, crisp clean silhouette legible when only 64 pixels wide. Composition: square canvas, head centered, ears and whiskers entirely within frame, head occupies 86 percent of width, no body, no neck, no props. Actual transparent alpha background. No text, no border, no shadow outside the head, no logo, no reference to any existing branded character. This sprite will sit on colored square puzzle tiles.”
- `assets/Nunito.ttf`: Nunito, from Google Fonts. SIL Open Font License included as `assets/Nunito-OFL.txt`.
- `assets/icon.svg`: created for this project.
- Godot Engine: MIT license, included in `assets/Godot-LICENSE.txt`.

## Verification

Version 1.1.0 imported and exported for Windows and Android without script errors. An isolated preview upgraded a version 1 save with 15 completed puzzles to level 16 with three hearts, then advanced to level 17 with one heart; the saved totals increased to 16 puzzles and remained at one completed round. The packaged Windows executable passed a headless startup check. Android signature verification passed, its version is 1.1.0 (code 2), no audio files are packaged, and vibration remains its only requested permission. No Android device was connected for on-device verification.

Original 1.0 generation and rendering checks:

Godot imported and ran the project without script errors. Twelve independently seeded boards (four per difficulty) generated successfully, and each complete hint walkthrough was checked against the solution. A separate solver independently confirmed one solution for each board. All checked regions were connected, all cat arrangements met the rules, and all hint actions agreed with the solution. Those runs generated boards in 18–257 ms on this PC.

Windows rendering was inspected through Godot-captured images, including the packaged executable; its gameplay capture matched the source render pixel for pixel. Both targets use the compatibility renderer. Both release targets exported; Android signing verification passed and its permissions were inspected. Native Windows input automation could not activate the game window in this desktop session, and no Android device was connected. Full mouse/touch playthrough and on-device Android verification remain outstanding.
