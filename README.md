# StarCraft II Ultrawide Patch (21:9 / 32:9)

**English** · [中文](README.zh-CN.md)

## Install — one line · 一行安装

1. **Quit the game** (including the "StarCraft II" process inside Battle.net).
   **退出游戏**（包括战网里的「星际争霸 II」进程）。
2. **Run this single line in PowerShell**:
   **在 PowerShell 里运行这一行**：

```powershell
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/zhubaohi/SC2-Ultrawide-patch/main/sc2-ultrawide.ps1' -OutFile "$env:TEMP\sc2ulw.ps1"; powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\sc2ulw.ps1" apply
```

**Done when you see** `Read-back check: all patches in effect`.
**看到** `Read-back check: all patches in effect` **即成功**，启动游戏即可。

---

## 1. Requirements

| Item | Requirement |
|------|-------------|
| OS | Windows 10 / 11 (64-bit) |
| Runtime | Built-in Windows PowerShell 5.1, nothing extra to install |
| Game version | **5.0.17.98310**, **5.0.15.98370** or **5.0.17.98370** (auto-detected) |
| Display | Any common 21:9 / 32:9 ultrawide display (3440x1440, 5120x1440, …), or any resolution you specify |

> On a version mismatch the tool prints the disagreeing bytes and refuses to modify — no half-patched file is ever produced.
> Porting to a new version: see the "Porting Guide" at the end of `docs/技术分析.md` (Chinese).

## 2. Install & in-game setup

**The one-line install at the top of this page is the only way to patch** — it
downloads the script to `%TEMP%` and applies it immediately (resolution is
auto-detected from your desktop). No repo clone, no extra files.

Recommended in-game settings:

```
Display mode = Windowed Fullscreen
Resolution   = your ultrawide display resolution (e.g. 5120x1440 / 3440x1440)
```

The config is written automatically by the patch (auto-detected from your desktop);
you normally don't need to touch it.

### No restart? Live injection

While the game is running, run the same one-liner with **`live`** instead of
`apply`:

```powershell
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/zhubaohi/SC2-Ultrawide-patch/main/sc2-ultrawide.ps1' -OutFile "$env:TEMP\sc2ulw.ps1"; powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\sc2ulw.ps1" live
```

It injects the patch into the process memory and makes the game recompute its
window at the new size immediately. Caveat: it does not survive a game exit —
run it again after the next launch. Use the `apply` one-liner for the permanent
fix.

> Note: on **5.0.17.98310** the label strings and aspect-ratio constants live on
> read-only pages (`.rdata`), which the engine protects at runtime, so full memory
> injection is impossible there. `live` detects this and refuses **before writing a
> single byte** (zero writes, no half-patched state). On 98310, quit the game and use
> the `apply` one-liner (the file patch) — that is the reliable path. Details in
> `docs/技术分析.md` §10.4 (Chinese).

### In-game verification (after apply)

1. Launch the game and open **Options → Video**.
2. The resolution dropdown must show the 6 new ultrawide entries at the top:
   `2560x1080`, `3440x1440`, `5120x1440`, `3840x1600`, `5120x2160`, `3840x1080`.
3. Select **5120x1440** and set display mode to **Windowed Fullscreen**.
4. The window should fill the entire 5120x1440 desktop edge to edge (32:9).

If the window gets clamped back to 16:9, see the FAQ below.

## 3. Parameters

```powershell
.\sc2-ultrawide.ps1 [status|apply|revert|live|help] [-Exe <path>] [-Config <path>] [-Width N] [-Height N] [-DryRun]
```

| Parameter | Meaning |
|---|---|
| `-Exe <path>` | Manually specify `SC2_x64.exe` (when auto-detection fails) |
| `-Config <path>` | Manually specify `Variables.txt` |
| `-Width` / `-Height` | Target resolution. **Omit to auto-detect the primary display** (it must be one of the injected 21:9/32:9 entries; 5120x1440 is the fallback) |
| `-DryRun` | Show what would change; write nothing |

Custom resolution examples:

```powershell
.\sc2-ultrawide.ps1 apply -Width 3440 -Height 1440
.\sc2-ultrawide.ps1 apply -Width 2560 -Height 1080
```

> The engine packs resolutions into 14-bit fields (max 16383 per axis); values above that are rejected.

## 4. What exactly gets patched

Three patch classes, all about "freeing the ultrawide format from the hard-coded 16:9 limits".
Patch tables are per-version (RVAs differ by version); every site is byte-verified before writing — mismatched versions are refused.

**1) Resolution dropdown table: rewrite the low-end entries**

The engine's resolution table is a fixed 17 entries (24 bytes each: width, height, label-begin pointer, label-end pointer).
The low-end entries unused on a 5120x1440 display (480p / 640x480 class) are overwritten with popular ultrawide resolutions;
the `3840x2160` entry is left untouched. The dropdown still has 17 entries; the game's original logic is unaffected.

Each entry gets 4 edits: width (4 bytes), height (4 bytes), label string (16 bytes, e.g. `"@UI/480x360"` → `"2560x1080"`),
label-end pointer (8 bytes, follows the new string length). The default 6 entries (editable via `$UltrawideRes` at the top of
`sc2-ultrawide.ps1`, ≤ 6 items):

| Entry (original) | New resolution |
|---|---|
| 0 (480x360) | 2560x1080 |
| 1 (640x360) | 3440x1440 |
| 2 (640x480) | **5120x1440** |
| 3 (640x512) | 3840x1600 |
| 4 (800x600) | 5120x2160 |
| 5 (960x540) | 3840x1080 |

**5.0.17.98310** (the default target of this patch; 4 sites per entry 0–5, 24 total):

| Entry | W | H | Label | Label-end ptr |
|---|---|---|---|---|
| 0 | `0x03920860` | `0x03920864` | `0x02E6F660` | `0x03920870` |
| 1 | `0x03920878` | `0x0392087C` | `0x02E6F670` | `0x03920888` |
| 2 | `0x03920890` | `0x03920894` | `0x02E6F680` | `0x039208A0` |
| 3 | `0x039208A8` | `0x039208AC` | `0x02E6F690` | `0x039208B8` |
| 4 | `0x039208C0` | `0x039208C4` | `0x02E6F6A0` | `0x039208D0` |
| 5 | `0x039208D8` | `0x039208DC` | `0x02E6F6B0` | `0x039208E8` |

**5.0.15.98370 / 5.0.17.98370** (legacy compatibility table; 4 sites per entry 0–3, 16 total):

| Entry | W | H | Label | Label-end ptr |
|---|---|---|---|---|
| 0 | `0x3BD8090` | `0x3BD8094` | `0x2BF2700` | `0x3BD80A0` |
| 1 | `0x3BD80A8` | `0x3BD80AC` | `0x2BF2710` | `0x3BD80B8` |
| 2 | `0x3BD80C0` | `0x3BD80C4` | `0x2BF2720` | `0x3BD80D0` |
| 3 | `0x3BD80D8` | `0x3BD80DC` | `0x2BF2730` | `0x3BD80E8` |

**2) Aspect-ratio cap: float constants (2 on 98370, 3 candidates relaxed on 98310)**

The engine hard-codes a 16:9 aspect-ratio cap (~1.7778f) in two places: one in the
**resolution-parsing function** (resolutions over the cap are rejected outright), one in the
**window-sizing function** (**critical**: in borderless mode the window gets clamped back to a
16:9 strip; the D3D9 back buffer follows the window, so the render resolution gets clamped too).
The patch rewrites these floats to `W/H + 0.05` tolerance computed from the target resolution
(5120x1440 → 3.6056f).

**3) Quality preset threshold: 1 instruction (98370 series only)**

The 98370 resolution-parsing function has a `cmp reg, 5` preset gate (only presets 0–5 go through
the parsing logic); the patch changes it to `cmp reg, 7` so custom quality presets can parse resolutions.
**Not applicable to 98310**: that version's `.text` section is ciphertext (decrypted at runtime,
PE entry point = 0), so instruction-level patches cannot land in the on-disk file; an exhaustive
static scan (all 13 `cmp reg,5` sites checked) found no 98370-shaped gate — presumably removed in
source. The 98310 table is therefore 27 pure data sites (24 table entries + 3 float constants);
see `docs/技术分析.md` §7 and §9 (Chinese).

Function/constant RVAs per version:

| Version | Parse cap (f32) | Preset gate (cmp 5→7) | Window cap (f32) |
|---|---|---|---|
| 5.0.17.98310 | `0x02E7BC80` | N/A (code section encrypted) | `0x02FB72A0` + `0x02D06700` |
| 5.0.1x.98370 | `0x2BFC1D0` | `0x118125E` | `0x2C2A588` |

All three 98310 float candidates (all 16:9-class cap constants) are relaxed to `W/H + 0.05`:
this covers both the "parse cap" and the "window clamp" paths; if one turns out unreferenced it is harmless.

Config is written to `%USERPROFILE%\Documents\StarCraft II\Variables.txt`:

```
displaymode=1      # 0=windowed 1=windowed fullscreen 2=exclusive fullscreen
width=5120
height=1440
windowx=0
windowy=0
windowwidth=5120
windowheight=1440
```

Full derivation (decompilation evidence, runtime forensics, 98310 adaptation log):
**`docs/技术分析.md`** (Chinese).

## 5. Reverting

Run the same one-liner with **`revert`** instead of `apply`:

```powershell
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/zhubaohi/SC2-Ultrawide-patch/main/sc2-ultrawide.ps1' -OutFile "$env:TEMP\sc2ulw.ps1"; powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\sc2ulw.ps1" revert
```

Backups: `SC2_x64.exe.sc2uw.bak` and `Variables.txt.sc2uw.bak`.
Battle.net's "Scan and Repair" also restores the official files.

The config is not auto-reverted (the resolution setting itself is harmless); if you want it back,
restore the corresponding lines from the `.sc2uw.bak`.

## 6. FAQ

**Q: "SC2_x64.exe not found"**
Specify it with `-Exe`; the path is usually `<install>\Versions\Base98310\SC2_x64.exe`.
Alternatively, launch the game once first — the tool reads the `ExecuteInfo.txt` the game writes to
`Documents\StarCraft II`.

**Q: "The file's bytes do not match any supported version"**
Game version and patch don't match (e.g. Battle.net just updated it). The file is **not** damaged.
Either wait for a patch update for the new version, or use the `revert` one-liner / Battle.net
Scan & Repair to restore the official file.

**Q: Patched, but the in-game window still doesn't fill the screen**
1. Run the same one-liner with `status` and confirm every site says `patched`;
2. Confirm the in-game display mode is **Windowed Fullscreen** (not "Fullscreen", not "Windowed");
3. Confirm the Windows desktop resolution is exactly 5120x1440 (after the dual-monitor setup).

**Q: Why rewrite the low-end entries instead of adding a new one?**
The table is a fixed 17 entries with adjacent data in memory; it can't be extended in place.
The low-end entries (480p class) are unusable on a 5120x1440 display anyway — zero impact on
normal use. The `3840x2160` entry is preserved untouched.

**Q: It stopped working after a Battle.net update / Scan & Repair?**
Normal — updates overwrite `SC2_x64.exe`. Just run the `apply` one-liner again (a new version
may need re-adaptation first).

**Q: Will anti-cheat detect this?**
The `apply` one-liner only modifies static bytes in the local executable — no memory writes,
no process injection; lowest risk. `live` does write into the game process memory; prefer the
`apply` one-liner if you are concerned.

## 7. Files

```
sc2-ultrawide.ps1      Main program (status / apply / revert / live, dual-version adaptive)
README.md              This file (English)
README.zh-CN.md        Chinese documentation
docs/技术分析.md        Root cause, patch tables, forensics, 98310 adaptation, porting guide (Chinese)
```

## 8. Disclaimer

The patch targets the local client and local file behavior (single-player/menu context). It modifies
local files only; a backup is made automatically before patching and can be restored anytime.
Re-adaptation is required after a game version update.

**The author is not liable for any consequences of using this patch, including
account bans.** Any risk (account, files, hardware) is yours alone — you use this
modification entirely at your own risk.