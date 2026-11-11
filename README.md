# StarCraft II Ultrawide Patch (21:9 / 32:9)

**English** · [中文](README.zh-CN.md)

## Install in one line

1. **Quit the game** (close Battle.net, or quit StarCraft II from inside it). The game process must be gone: while the game is running, Windows locks its executable, so the patch cannot be written.
2. **Open PowerShell**: press the Windows key, type `PowerShell`, press Enter.
3. **Paste this line and press Enter**:

```powershell
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/zhubaohi/SC2-Ultrawide-patch/main/sc2-ultrawide.ps1' -OutFile "$env:TEMP\sc2ulw.ps1"; powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\sc2ulw.ps1" apply
```

4. You are done when you see `Read-back check: all patches in effect`. Launch the game from Battle.net and pick your ultrawide resolution in **Options → Video**.

That line is the whole install: it downloads the patch script to a temp folder, applies the patch, and writes the game config for you. Nothing else to do.

---

StarCraft II refuses to draw past 16:9 in windowed mode, so on a 21:9 or 32:9 monitor the game
shows up as a letterboxed strip in the middle of the desktop. This patch tweaks a handful of
hard-coded limits inside the game executable so the engine accepts your ultrawide resolution in
borderless windowed mode.

- Pure PowerShell: the target machine only needs the built-in Windows PowerShell 5.1, nothing to install.
- The original files are backed up before anything is touched, and reverting is one command.
- The game version is detected from the file bytes; on a mismatch the script refuses and never leaves a half patched file behind.
- It can also inject the patch into a running game (on supported versions), so no restart is needed.

> **Credit**: this project builds on the original work in [this NGA post](https://bbs.nga.cn/read.php?tid=47835650).

## 1. Requirements

| Item | Requirement |
|------|-------------|
| OS | Windows 10 or 11 (64-bit) |
| Runtime | Windows PowerShell 5.1, built into the OS, nothing extra to install |
| Game version | 5.0.17.98310, 5.0.15.98370 or 5.0.17.98370 (auto-detected) |
| Display | Any common 21:9 or 32:9 ultrawide display (3440x1440, 5120x1440 and friends), or any resolution you specify |

Two things worth knowing up front:

- On a version mismatch the tool prints the disagreeing bytes and refuses to write, so a corrupted file is not on the table.
- Porting to a new game version: see the "Porting Guide" at the end of the technical log in `docs/` (written in Chinese).

## 2. Setup and in-game settings

The one line at the top of this page is the whole install: it downloads the script to `%TEMP%`
and applies the patch right away, with the resolution auto-detected from your desktop.
No repo clone, no extra files.

After patching, keep these settings in game:

```
Display mode = Windowed Fullscreen
Resolution   = your ultrawide resolution (for example 5120x1440 or 3440x1440)
```

The patch writes the config for you, so you should not need to touch it.

### Game already running? Inject without a restart

Swap the `apply` at the end of the one line for `live`:

```powershell
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/zhubaohi/SC2-Ultrawide-patch/main/sc2-ultrawide.ps1' -OutFile "$env:TEMP\sc2ulw.ps1"; powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\sc2ulw.ps1" live
```

This writes the patch straight into the game's memory and makes it resize the window immediately.
The catch is that it does not survive a game exit, so run it again after the next launch.
For the permanent fix, quit the game and use the `apply` line.

> One important note for **5.0.17.98310**: on this version the label strings and aspect ratio
> constants sit on read-only pages (`.rdata`) that the engine protects at runtime, so a full
> memory injection is impossible. `live` detects this and refuses before writing a single byte,
> which keeps the process clean. On 98310, quit the game and use the `apply` line instead.
> That is the reliable path there; the technical log in `docs/` (section 10.4, Chinese) has the details.

### Checking it in game (after apply)

1. Launch the game and open **Options → Video**.
2. The resolution dropdown should show six new ultrawide entries at the top:
   `2560x1080`, `3440x1440`, `5120x1440`, `3840x1600`, `5120x2160`, `3840x1080`.
3. Pick **5120x1440** and set the display mode to **Windowed Fullscreen**.
4. The window should fill the entire 5120x1440 desktop, edge to edge (32:9).

If the window snaps back to 16:9, the FAQ below should cover it.

## 3. Parameters

```powershell
.\sc2-ultrawide.ps1 [status|apply|revert|live|help] [-Exe <path>] [-Config <path>] [-Width N] [-Height N] [-DryRun]
```

| Parameter | Meaning |
|---|---|
| `-Exe <path>` | Point the tool at `SC2_x64.exe` manually (only if auto-detection fails) |
| `-Config <path>` | Point it at a specific `Variables.txt` |
| `-Width` / `-Height` | Target resolution. Leave them out and the tool auto-detects your primary display; it must be one of the injected 21:9/32:9 entries, and 5120x1440 is the fallback |
| `-DryRun` | Show what would change, write nothing |

For example:

```powershell
.\sc2-ultrawide.ps1 apply -Width 3440 -Height 1440
.\sc2-ultrawide.ps1 apply -Width 2560 -Height 1080
```

Heads up: the engine stores resolutions in 14-bit fields, so each axis caps at 16383,
and anything above that is rejected.

## 4. What exactly gets patched

Three groups of changes, all in service of one goal: freeing the ultrawide format from the
hard-coded 16:9 limits. Every version has its own patch table (the offsets differ), and each
site is byte-verified before writing, so a version mismatch is refused before anything happens.

**1) The resolution dropdown: low-end entries get rewritten**

The engine's resolution table is fixed at 17 entries (24 bytes each: width, height, pointer to
the label start, pointer to the label end). The low-end entries that are useless on a 5120x1440
display (the 480p and 640x480 class) get overwritten with popular ultrawide resolutions, while
the `3840x2160` entry is left alone. The dropdown still has 17 entries and the game's original
logic is untouched.

Each entry receives four edits: the width (4 bytes), the height (4 bytes), the label string
(16 bytes, e.g. `"@UI/480x360"` becomes `"2560x1080"`), and the label-end pointer (8 bytes,
which follows the new string length). The default six entries (editable in `$UltrawideRes` at
the top of `sc2-ultrawide.ps1`, up to 6 items) are:

| Entry (original) | New resolution |
|---|---|
| 0 (480x360) | 2560x1080 |
| 1 (640x360) | 3440x1440 |
| 2 (640x480) | **5120x1440** |
| 3 (640x512) | 3840x1600 |
| 4 (800x600) | 5120x2160 |
| 5 (960x540) | 3840x1080 |

**5.0.17.98310** (the default target of this patch; four sites per entry, entries 0 to 5, 24 sites in total):

| Entry | W | H | Label | Label-end ptr |
|---|---|---|---|---|
| 0 | `0x03920860` | `0x03920864` | `0x02E6F660` | `0x03920870` |
| 1 | `0x03920878` | `0x0392087C` | `0x02E6F670` | `0x03920888` |
| 2 | `0x03920890` | `0x03920894` | `0x02E6F680` | `0x039208A0` |
| 3 | `0x039208A8` | `0x039208AC` | `0x02E6F690` | `0x039208B8` |
| 4 | `0x039208C0` | `0x039208C4` | `0x02E6F6A0` | `0x039208D0` |
| 5 | `0x039208D8` | `0x039208DC` | `0x02E6F6B0` | `0x039208E8` |

**5.0.15.98370 / 5.0.17.98370** (the legacy compatibility table; four sites per entry, entries 0 to 3, 16 sites in total):

| Entry | W | H | Label | Label-end ptr |
|---|---|---|---|---|
| 0 | `0x3BD8090` | `0x3BD8094` | `0x2BF2700` | `0x3BD80A0` |
| 1 | `0x3BD80A8` | `0x3BD80AC` | `0x2BF2710` | `0x3BD80B8` |
| 2 | `0x3BD80C0` | `0x3BD80C4` | `0x2BF2720` | `0x3BD80D0` |
| 3 | `0x3BD80D8` | `0x3BD80DC` | `0x2BF2730` | `0x3BD80E8` |

**2) The aspect ratio cap: float constants (2 on 98370, 3 relaxed candidates on 98310)**

The engine hard-codes a 16:9 aspect ratio cap (about 1.7778f) in two places. One sits in the
resolution parsing function, where any resolution over the cap is rejected outright. The other
sits in the window sizing function, and this one is the important one: in borderless mode the
window gets clamped back to a 16:9 strip, the D3D9 back buffer follows the window, and the
render resolution gets clamped along with it. The patch rewrites these floats to a
`W/H + 0.05` tolerance computed from the target resolution (5120x1440 becomes 3.6056f).

**3) The quality preset threshold: one instruction (98370 series only)**

The 98370 resolution parsing function contains a `cmp reg, 5` preset gate (only presets 0 to 5
pass through the parsing logic). The patch changes it to `cmp reg, 7` so custom quality presets
can resolve resolutions too.

**98310 does not have this**: its `.text` section is ciphertext (decrypted at runtime, PE entry
point is 0), so instruction-level patches cannot land in the on-disk file. An exhaustive static
scan (all 13 `cmp reg,5` sites checked) found no 98370-shaped gate, so it was presumably removed
in source. That is why the 98310 table is 27 pure data sites (24 table entries plus 3 float
constants). See the technical log in `docs/` (sections 7 and 9, Chinese).

Function and constant offsets per version:

| Version | Parse cap (f32) | Preset gate (cmp 5 to 7) | Window cap (f32) |
|---|---|---|---|
| 5.0.17.98310 | `0x02E7BC80` | not applicable (code section encrypted) | `0x02FB72A0` + `0x02D06700` |
| 5.0.1x.98370 | `0x2BFC1D0` | `0x118125E` | `0x2C2A588` |

All three 98310 float candidates (all 16:9-class cap constants) get relaxed to `W/H + 0.05`.
That covers both the parse cap and the window clamp paths, and if one of them turns out to be
unreferenced it is harmless.

The config is written to `%USERPROFILE%\Documents\StarCraft II\Variables.txt`:

```
displaymode=1      # 0=windowed 1=windowed fullscreen 2=exclusive fullscreen
width=5120
height=1440
windowx=0
windowy=0
windowwidth=5120
windowheight=1440
```

The full derivation (decompilation evidence, runtime forensics, the 98310 adaptation log)
lives in the technical log in `docs/` (Chinese).

## 5. Reverting

Swap the `apply` at the end of the one line for `revert`:

```powershell
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/zhubaohi/SC2-Ultrawide-patch/main/sc2-ultrawide.ps1' -OutFile "$env:TEMP\sc2ulw.ps1"; powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\sc2ulw.ps1" revert
```

Backups live at `SC2_x64.exe.sc2uw.bak` and `Variables.txt.sc2uw.bak`.
Battle.net's "Scan and Repair" also restores the official files.

The config is not reverted automatically (the resolution setting itself is harmless).
If you want it back, restore the corresponding lines from the `.sc2uw.bak` file.

## 6. FAQ

**"SC2_x64.exe not found"**
Point the tool at it with `-Exe`; the path is usually `<install>\Versions\Base98310\SC2_x64.exe`.
Or launch the game once first: the tool reads the `ExecuteInfo.txt` the game writes to
`Documents\StarCraft II`.

**"The file's bytes do not match any supported version"**
The game version and the patch do not match (Battle.net probably just updated the game).
The file is **not** damaged. Either wait for the patch to be adapted to the new version, or use
the `revert` line or Battle.net's Scan and Repair to restore the official file.

**Patched, but the in-game window still does not fill the screen**
1. Run the one line with `status` and confirm every site says `patched`.
2. Confirm the in-game display mode is **Windowed Fullscreen** (not "Fullscreen", not "Windowed").
3. Confirm the Windows desktop resolution is exactly 5120x1440 after the dual-monitor setup.

**Why rewrite the low-end entries instead of adding a new one?**
The table is fixed at 17 entries with adjacent data right next to it in memory, so it cannot be
extended in place. The low-end entries (the 480p class) are unusable on a 5120x1440 display
anyway, so rewriting them has zero impact on normal use. The `3840x2160` entry is preserved
untouched.

**It stopped working after a Battle.net update or Scan and Repair**
That is expected: updates overwrite `SC2_x64.exe`. Just run the `apply` line again (a new
version may need to be adapted first).

**Will anti-cheat detect this?**
The `apply` line only changes static bytes in the local executable: no memory writes, no process
injection, which is the lowest risk option. `live` does write into the game's process memory, so
if that matters to you, stick with the `apply` line.

## 7. Files

- `sc2-ultrawide.ps1`: the main program (status / apply / revert / live, adapts to both game versions)
- `README.md`: this file (English)
- `README.zh-CN.md`: the Chinese version of this documentation
- `docs/`: the technical log (Chinese): root cause, patch tables, forensics, 98310 adaptation, porting guide

## 8. Disclaimer

This patch targets the local client and local file behavior (single-player and menu context).
It only touches local files, a backup is made automatically before patching and can be restored
at any time, and a game version update will require re-adaptation.

**The author is not liable for any consequences of using this patch, including account bans.**
Any risk (account, files, hardware) is yours alone; you use this modification entirely at your
own risk.
