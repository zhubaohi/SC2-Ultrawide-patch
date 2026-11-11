# StarCraft II Ultrawide Patch (21:9 / 32:9)

**[English](#english) · [中文](#中文)**

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

A byte patch that lets StarCraft II render at a true 21:9 / 32:9 ultrawide
resolution in **borderless windowed** mode, instead of being clamped back to
16:9 by the engine.
It covers the common 21:9 / 32:9 setups out of the box and **auto-detects your
desktop resolution**, so you normally don't have to pass any arguments.

- Pure PowerShell — **no Python or extra runtimes needed on the target machine**
- Automatic backup before patching; one-click revert
- Game version auto-detected from on-disk bytes; a version mismatch is refused outright — the file is never corrupted
- Can inject into a **running** game (no restart) on supported versions

> **Credit**: this project was built on top of the original work in [this NGA
> post](https://bbs.nga.cn/read.php?tid=47835650).

---

## English

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
README.md              This file (English / 中文)
docs/技术分析.md        Root cause, patch tables, forensics, 98310 adaptation, porting guide (Chinese)
```

## 8. Disclaimer

The patch targets the local client and local file behavior (single-player/menu context). It modifies
local files only; a backup is made automatically before patching and can be restored anytime.
Re-adaptation is required after a game version update.

**The author is not liable for any consequences of using this patch, including
account bans.** Any risk (account, files, hardware) is yours alone — you use this
modification entirely at your own risk.

---

## 中文

让《星际争霸2》在**带鱼屏**（21:9 / 32:9 超宽屏，如 5120x1440、3440x1440、3840x1600）上
真正以超宽比例渲染（窗口化全屏），而不是被引擎强行夹回 16:9。
常用带鱼屏分辨率开箱即用，**自动检测你的桌面分辨率**，一般不需要传任何参数。

- 纯 PowerShell 实现，**目标机器不需要安装 Python 或任何运行库**
- 改前自动备份，一条命令还原
- 按字节自动识别游戏版本，版本不符直接拒绝，不会写坏文件
- 支持对**正在运行的游戏**注入（不用重启）

> **致谢**：本作品是在 [NGA 这篇帖子](https://bbs.nga.cn/read.php?tid=47835650) 的原创作品基础上完成的。

### 一、系统要求

| 项目 | 要求 |
|------|------|
| 系统 | Windows 10 / 11（64 位） |
| 运行环境 | 自带的 Windows PowerShell 5.1，无需额外安装 |
| 游戏版本 | **5.0.17.98310**、**5.0.15.98370** 或 **5.0.17.98370**（自动识别） |
| 显示器 | 任意常用 21:9 / 32:9 带鱼屏（3440x1440、5120x1440 等），或任意你指定的分辨率 |

> 版本不符时工具会列出不符的字节并拒绝修改，不会产生半成品文件。
> 想移植到新版本，见 `docs/技术分析.md` 末尾的「版本适配指南」。

### 二、安装与游戏内设置

**页面顶部的「一行安装」是本补丁唯一的安装方式** —— 脚本下载到 %TEMP% 并立即打补丁
（分辨率自动检测），无需克隆仓库、无需额外文件。

游戏内的设置建议保持为：

```
显示模式 = 窗口化全屏
分辨率   = 你的带鱼屏分辨率（如 5120x1440 / 3440x1440）
```

配置由补丁自动写入（桌面分辨率自动检测），一般不需要手动改。

#### 不想重启游戏？

游戏正在运行时，跑同一行命令（把末尾的 `apply` 换成 **`live`**）：

```powershell
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/zhubaohi/SC2-Ultrawide-patch/main/sc2-ultrawide.ps1' -OutFile "$env:TEMP\sc2ulw.ps1"; powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\sc2ulw.ps1" live
```

它会把补丁直接注入进程内存，并让游戏立刻按新尺寸重算窗口。
缺点是退出游戏后失效，下次启动要再点一次；想一劳永逸就用 `apply` 一行命令。

> 注意：**5.0.17.98310** 的标签字符串与宽高比常量位于只读页（`.rdata`），引擎在运行时
> 保护这些内存常量，无法完整注入。`live` 会在写入任何字节之前自动检测并明确拒绝
> （零写入、不留半补丁状态）。此时请退出游戏用 `apply` 一行命令（文件补丁），
> 这是 98310 的可靠路径。详见 `docs/技术分析.md` 第十节第 4 小节。

#### 游戏内验证（apply 之后）

1. 启动游戏，打开 **选项 → 视频**。
2. 分辨率下拉表顶部必须出现 6 个新的带鱼屏选项：
   `2560x1080`、`3440x1440`、`5120x1440`、`3840x1600`、`5120x2160`、`3840x1080`。
3. 选中 **5120x1440**，显示模式设为**窗口化全屏**。
4. 窗口应铺满整个 5120x1440 桌面（32:9 边到边）。

如果窗口被夹回 16:9，见下方常见问题。

### 三、参数

```powershell
.\sc2-ultrawide.ps1 [status|apply|revert|live|help] [-Exe <路径>] [-Config <路径>] [-Width N] [-Height N] [-DryRun]
```

| 参数 | 说明 |
|---|---|
| `-Exe <路径>` | 手动指定 `SC2_x64.exe`（自动查找失败时用） |
| `-Config <路径>` | 手动指定 `Variables.txt` |
| `-Width` / `-Height` | 目标分辨率。**省略则自动检测主显示器**（须为内置的 21:9/32:9 选项之一，检测失败时回退 5120x1440） |
| `-DryRun` | 只演练不写入 |

自定义分辨率示例：

```powershell
.\sc2-ultrawide.ps1 apply -Width 3440 -Height 1440
.\sc2-ultrawide.ps1 apply -Width 2560 -Height 1080
```

> 引擎把分辨率打包进 14 位字段，每轴上限 16383，超出会被拒绝。

### 四、它到底改了什么

三类补丁，全部围绕「把带鱼屏从写死的 16:9 限制里放出来」。
补丁表按版本各一套（RVA 随版本不同），工具写前逐点按字节校验，版本不符直接拒绝。

**1）分辨率下拉表：改写低档条目**

引擎的分辨率表是写死的 17 项（每项 24 字节：宽、高、标签头指针、标签尾指针）。
5120x1440 带鱼屏上用不到的低档条目（480p / 640x480 一类）被覆盖成常用超宽分辨率，
`3840x2160` 那档保留不动，下拉表仍是 17 项，游戏原有逻辑不受影响。

每格条目改 4 处：宽（4 字节）、高（4 字节）、标签字符串（16 字节，如 `"@UI/480x360"` → `"2560x1080"`）、
标签尾指针（8 字节，跟随新字符串长度）。默认 6 格如下，可在 `sc2-ultrawide.ps1`
顶部的 `$UltrawideRes` 自行增删（≤6 项）：

| 条目（原分辨率） | 新分辨率 |
|---|---|
| 0（480x360） | 2560x1080 |
| 1（640x360） | 3440x1440 |
| 2（640x480） | **5120x1440** |
| 3（640x512） | 3840x1600 |
| 4（800x600） | 5120x2160 |
| 5（960x540） | 3840x1080 |

**5.0.17.98310**（本补丁默认适配的目标，条目 0–5 各 4 处，共 24 处）：

| 条目 | 宽 | 高 | 标签 | 标签尾指针 |
|---|---|---|---|---|
| 0 | `0x03920860` | `0x03920864` | `0x02E6F660` | `0x03920870` |
| 1 | `0x03920878` | `0x0392087C` | `0x02E6F670` | `0x03920888` |
| 2 | `0x03920890` | `0x03920894` | `0x02E6F680` | `0x039208A0` |
| 3 | `0x039208A8` | `0x039208AC` | `0x02E6F690` | `0x039208B8` |
| 4 | `0x039208C0` | `0x039208C4` | `0x02E6F6A0` | `0x039208D0` |
| 5 | `0x039208D8` | `0x039208DC` | `0x02E6F6B0` | `0x039208E8` |

**5.0.15.98370 / 5.0.17.98370**（旧版适配表，条目 0–3 各 4 处，共 16 处）：

| 条目 | 宽 | 高 | 标签 | 标签尾指针 |
|---|---|---|---|---|
| 0 | `0x3BD8090` | `0x3BD8094` | `0x2BF2700` | `0x3BD80A0` |
| 1 | `0x3BD80A8` | `0x3BD80AC` | `0x2BF2710` | `0x3BD80B8` |
| 2 | `0x3BD80C0` | `0x3BD80C4` | `0x2BF2720` | `0x3BD80D0` |
| 3 | `0x3BD80D8` | `0x3BD80DC` | `0x2BF2730` | `0x3BD80E8` |

**2）宽高比上限：浮点常量（98370 为 2 处，98310 放宽 3 处候选）**

引擎在 2 处写死了 16:9 的宽高比上限（约 1.7778f）：一处在**分辨率解析函数**
（宽高比超限的分辨率直接拒收），一处在**窗口尺寸函数**（**关键**：窗口化全屏下
窗口被夹回 16:9 的细条，D3D9 背景缓冲跟着窗口走，渲染分辨率也被夹掉）。
补丁把这些浮点改成按目标分辨率动态计算的 `W/H + 0.05` 容差（5120x1440 → 3.6056f）。

**3）画质预设门槛：1 条指令（仅 98370 系列）**

98370 的分辨率解析函数里有一条 `cmp reg, 5` 预设门槛（只有预设档 0–5 会走解析逻辑），
补丁改成 `cmp reg, 7`，自定义画质档也能解析分辨率。
**98310 不适用**：该版本 `.text` 段是密文（运行时解密加载，PE 入口点为 0），
指令级补丁无法落在磁盘文件上；且静态穷尽扫描（13 处 `cmp reg,5` 全部校验）
未发现 98370 形状的门槛，疑似源码中已移除。98310 补丁表因此为 27 处纯数据站点
（24 处表条目 + 3 处浮点常量），见 `docs/技术分析.md` 第七、九节。

各版本函数/常量点的 RVA：

| 版本 | 解析上限（f32） | 预设门槛（cmp 5→7） | 窗口上限（f32） |
|---|---|---|---|
| 5.0.17.98310 | `0x02E7BC80` | 不适用（代码段密文） | `0x02FB72A0` + `0x02D06700` |
| 5.0.1x.98370 | `0x2BFC1D0` | `0x118125E` | `0x2C2A588` |

98310 的三个浮点候选（均为 16:9 类上限常量）全部放宽到 `W/H + 0.05`：
覆盖「解析上限 + 窗口夹取」两条路径，即使某处未被代码引用也无害。

配置写入 `%USERPROFILE%\Documents\StarCraft II\Variables.txt`：

```
displaymode=1      # 0=窗口化 1=窗口化全屏 2=独占全屏
width=5120
height=1440
windowx=0
windowy=0
windowwidth=5120
windowheight=1440
```

完整推导过程（含反编译证据、运行时取证方法、98310 适配记录）见 **`docs/技术分析.md`**。

### 五、还原

跑同一行命令（把末尾的 `apply` 换成 **`revert`**）：

```powershell
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/zhubaohi/SC2-Ultrawide-patch/main/sc2-ultrawide.ps1' -OutFile "$env:TEMP\sc2ulw.ps1"; powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\sc2ulw.ps1" revert
```

备份文件在 `SC2_x64.exe.sc2uw.bak` 与 `Variables.txt.sc2uw.bak`。
也可以用战网客户端的「扫描与修复」恢复官方文件。

配置文件不会自动还原（分辨率设置本身无害），需要的话手动删掉备份里的对应行。

### 六、常见问题

**Q：提示「没有找到 SC2_x64.exe」**
用 `-Exe` 手动指定，路径一般在 `<安装目录>\Versions\Base98310\SC2_x64.exe`。
也可以先启动一次游戏，工具会读取游戏自己写的 `Documents\StarCraft II\ExecuteInfo.txt`。

**Q：提示「该文件的字节与支持版本不符」**
游戏版本和补丁不匹配（比如战网刚更新过）。**不会**写坏文件。此时要么等补丁适配新版本，
要么用 `revert` 一行命令 / 战网扫描修复恢复官方文件。

**Q：打完补丁，游戏里窗口还是没铺满**
1. 跑同一行命令（加 `status`）确认所有补丁点都是 `patched`；
2. 确认游戏里「显示模式」是**窗口化全屏**（不是「全屏」，也不是「窗口化」）；
3. 确认 Windows 显示设置里桌面分辨率就是 5120x1440（双屏拼接后）。

**Q：为什么不新增一项，而是改低档条目？**
分辨率表是写死的 17 项、内存里紧邻其它数据，无法原地追加。低档条目（480p 一类）在
5120x1440 带鱼屏上本来就用不了，改它们对正常使用零影响；`3840x2160` 那档原样保留。

**Q：战网更新/扫描修复后失效了？**
正常。更新会覆盖 `SC2_x64.exe`，重新运行 `apply` 一行命令即可（新版本可能需要重新适配）。

**Q：会被反作弊检测吗？**
`apply` 一行命令只修改本地可执行文件的静态字节，不改内存、不注入进程，风险最低。
`live` 会写入游戏进程内存，如在意请优先用 `apply` 一行命令。

### 七、文件清单

```
sc2-ultrawide.ps1      主程序（status / apply / revert / live，双版本自适应）
README.md              本文件（English / 中文）
docs/技术分析.md        根因、补丁表、取证过程、98310 适配、版本适配指南（中文）
```

### 八、免责说明

补丁针对单机/菜单与本地客户端行为，修改的是本地文件。使用前已自动备份，可随时还原。
游戏版本更新后需重新适配。

**作者对使用本补丁导致的任何后果概不负责（包括封号）。** 使用本修改即代表你完全
自行承担风险（账号、文件、硬件）。
