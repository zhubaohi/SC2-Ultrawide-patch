#Requires -Version 5.1
# --------------------------------------------------------------------------
# Credit: built on top of the original work in the NGA post
#   https://bbs.nga.cn/read.php?tid=47835650
# --------------------------------------------------------------------------
<#
.SYNOPSIS
    StarCraft II ultrawide patch (6 ultrawide resolutions / borderless window)

.DESCRIPTION
    Byte-patches SC2_x64.exe and writes Variables.txt: replaces the 6 low-end
    entries at the front of the resolution dropdown table (480x360 / 640x360 /
    640x480 / 640x512 / 800x600 / 960x540, measured on 98310; the first 4 on
    98370) with 6 popular ultrawide resolutions, and lifts 3 in-function
    limits (aspect-ratio parse cap / quality preset threshold / window
    aspect-ratio clamp).

    High-end resolutions (including 3840x2160) are preserved; only the low-end
    slots are touched. Pure PowerShell, no Python required.

    Target resolution: auto-detected from the primary display by default, so
    any of the injected 21:9 / 32:9 setups works without arguments
    (5120x1440 is the fallback when detection fails or the desktop is not in
    the injected set).

    Ultrawide options injected (editable in $UltrawideRes at the top):
      2560x1080  (21:9)   3440x1440  (21:9)   5120x1440  (32:9)
      3840x1600  (21:9 4K) 5120x2160 (32:9 4K) 3840x1080 (32:9)

    Supported versions (auto-detected by byte comparison; picking the wrong
    version is rejected by mismatched bytes, never writes bad data):
      5.0.15.98370 / 5.0.17.98370  (x64 client, replaces the first 4 entries)
      5.0.17.98310                 (x64 client, replaces the first 6 entries)

    The aspect-ratio cap is not hardcoded to 3.0; it is computed dynamically
    as max(W/H) of the ultrawide set + a 0.05 tolerance (default set:
    3.5556 + 0.05), so 32:9 and 21:9 are both lifted to their real ratios and
    16:9 is not affected.

.PARAMETER Command
    status  show install location, version, patch and config state (default)
    apply   patch the exe + write the config (backed up first)
    revert  restore the exe from the backup
    live    memory-inject into the running game (no restart needed)
    help    show help

.PARAMETER Exe
    Path to SC2_x64.exe. Omit to auto-detect (ExecuteInfo.txt first, then
    common install roots).

.PARAMETER Config
    Path to Variables.txt. Omit for 'Documents\StarCraft II\Variables.txt'.

.PARAMETER Width
    Display/window width written to Variables.txt. Omit (together with
    -Height) to auto-detect the primary display; it must match one of the
    injected ultrawide entries, otherwise 5120 is the fallback. Does not
    affect the patch content.

.PARAMETER Height
    Display/window height written to Variables.txt. Omit (together with
    -Width) to auto-detect the primary display; 1440 is the fallback. Does
    not affect the patch content.

.PARAMETER DryRun
    Only show what would change; write nothing.

.EXAMPLE
    .\sc2-ultrawide.ps1 status
    .\sc2-ultrawide.ps1 apply
    .\sc2-ultrawide.ps1 live
    .\sc2-ultrawide.ps1 revert
    .\sc2-ultrawide.ps1 apply -Width 3440 -Height 1440   # only change the default window size in the config
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'apply', 'revert', 'live', 'help', 'install', 'restore', 'check')]
    [string]$Command = 'status',

    [string]$Exe,
    [string]$Config,

    [int]$Width = 0,
    [int]$Height = 0,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# --------------------------------------------------------------------------
# Ultrawide resolution set (the replacement targets)
# --------------------------------------------------------------------------
# The low-end entries at the front of the resolution table (the 360p-540p
# class) are replaced wholesale by the resolutions below.
# To add/remove options, edit this list: each item occupies one low-end
# entry (including its label). The more items, the more entries replaced.
# The aspect-ratio cap is computed dynamically as the max ratio in the set
# + 0.05 tolerance; nothing to tune per entry.
#
$script:UltrawideRes = @(
    @{ W = 2560; H = 1080 },   # 21:9  1080p
    @{ W = 3440; H = 1440 },   # 21:9  1440p
    @{ W = 5120; H = 1440 },   # 32:9  1440p (two 27" 16:9 panels side by side)
    @{ W = 3840; H = 1600 },   # 21:9  4K
    @{ W = 5120; H = 2160 },   # 32:9  4K
    @{ W = 3840; H = 1080 }    # 32:9  1080p
)
$script:ImageBase = [uint64]0x140000000

# --------------------------------------------------------------------------
# Patch tables (per version)
# --------------------------------------------------------------------------
#
# Table layout (same in both versions): 17 x 24-byte entries
# (u32 w; u32 h; ptr64 label begin; ptr64 label end);
# entry i is at table base + i*24; labels are 16-byte ASCII slots,
# slot base + i*16.
#
# Each version gets: table-entry sites (4 per entry: width/height/label text/
# label-end pointer) + 3 in-function sites (aspect-ratio parse cap / quality
# preset threshold / window aspect-ratio clamp cap).
# Site structure:
#   Name  description
#   Rva   offset within the image (RVA)
#   Old   original bytes (for comparison; 8-byte pointers are relocated by
#         the load-base delta during live injection)
#   New   post-patch bytes
#
# 98310 and 98370 have different compiled layouts, so each has its own RVA
# column set; the version is confirmed by comparing the Old bytes one by one.
# The low-end entries for 98310 are measured from the exe; the first 4 entries
# for 98370 come from the 98370 documentation (still compared one by one at
# runtime; a mismatch aborts the write).

function New-LabelBytes {
    param([string]$Text, [int]$SlotSize = 16)
    if ($Text.Length -ge $SlotSize) { throw "Label too long: $Text (slot is ${SlotSize} bytes)" }
    $b = New-Object byte[] $SlotSize
    $ascii = [System.Text.Encoding]::ASCII.GetBytes($Text)
    [Array]::Copy($ascii, $b, $ascii.Length)
    return $b
}

function New-EntrySites {
    # Generate 4N sites for the first $New.Count table entries
    # (width/height/label text/label-end pointer).
    # Label-end pointer = slot base + label length (following the original
    # table convention: points at the last character of the string).
    param([int]$TblBase, [int]$SlotBase, $Old, $New)
    $sites = @()
    for ($i = 0; $i -lt $New.Count; $i++) {
        $o = $Old[$i]; $n = $New[$i]
        $wRva = $TblBase + $i * 24
        $sRva = $SlotBase + $i * 16
        $oldLabel = $o.Label
        $newLabel = ($n.W.ToString() + 'x' + $n.H.ToString())
        $desc = "{0}x{1}->{2}x{3}" -f $o.W, $o.H, $n.W, $n.H
        $sites += @(
            @{ Name = ("entry {0} {1} W" -f $i, $desc)
                Rva = $wRva
                Old = (GetBytes-U32 $o.W); New = (GetBytes-U32 $n.W) },
            @{ Name = ("entry {0} {1} H" -f $i, $desc)
                Rva = ($wRva + 4)
                Old = (GetBytes-U32 $o.H); New = (GetBytes-U32 $n.H) },
            @{ Name = ("entry {0} label" -f $i)
                Rva = $sRva
                Old = (New-LabelBytes $oldLabel); New = (New-LabelBytes $newLabel) },
            @{ Name = ("entry {0} label end ptr" -f $i)
                Rva = ($wRva + 16)
                Old = (GetBytes-U64 ([uint64]($script:ImageBase + $sRva + $oldLabel.Length)))
                New = (GetBytes-U64 ([uint64]($script:ImageBase + $sRva + $newLabel.Length))) }
        )
    }
    return $sites
}

function Get-VersionProfiles {
    # Aspect-ratio cap: max ratio in the set + 0.05 tolerance (the engine
    # compares with a small float epsilon; leave plenty of headroom)
    $maxAr = ($UltrawideRes | ForEach-Object { [double]$_.W / [double]$_.H } |
        Measure-Object -Maximum).Maximum
    $cap = GetBytes-Single ([single]($maxAr + 0.05))

    # ---- 5.0.17.98310 ------------------------------------------------------
    # Table base 0x03920860 (.data), label slot base 0x02E6F660 (.rdata).
    # The first 6 low-end entries are measured from the exe:
    # 480x360 640x360 640x480 640x512 800x600 960x540.
    # NOTE: 98310's .text is ciphertext (whole-section entropy ~8.0, PE entry
    #       point = 0; SC2Switcher_x64.exe decrypts and loads it at runtime),
    #       so code-region sites cannot be located/patched on the on-disk
    #       file. This profile only covers data-section (.data/.rdata,
    #       plaintext) sites, all statically verifiable.
    $old98310 = @(
        @{ W = 480; H = 360; Label = '@UI/480x360' },
        @{ W = 640; H = 360; Label = '@UI/640x360' },
        @{ W = 640; H = 480; Label = '@UI/640x480' },
        @{ W = 640; H = 512; Label = '@UI/640x512' },
        @{ W = 800; H = 600; Label = '@UI/800x600' },
        @{ W = 960; H = 540; Label = '@UI/960x540' }
    )
    $sites98310 = New-EntrySites -TblBase 0x03920860 -SlotBase 0x02E6F660 -Old $old98310 -New $UltrawideRes
    # Aspect-ratio cap float constants, 3 candidates (98310 plaintext .rdata,
    # measured):
    #   0x02E7BC80 = 1.7777778f (parse cap candidate)
    #   0x02FB72A0 = 1.7777778f (window clamp candidate)
    #   0x02D06700 = 1.7786459f (same-value constant as 98370's window clamp,
    #                           adjacent to the WindowedFullscreen string)
    # All three are lifted to cap+0.05: covers both the "parse cap" and the
    # "window clamp" paths; even if one is unreferenced it is harmless
    # (they are all 16:9-class cap constants, and lifting is the right
    # direction).
    $sites98310 += @(
        @{ Name = 'AR cap (resolution parse)'; Rva = 0x02E7BC80
            Old = GetBytes-Single ([single]1.7777778); New = $cap },
        @{ Name = 'AR clamp (window, key)';    Rva = 0x02FB72A0
            Old = GetBytes-Single ([single]1.7777778); New = $cap },
        @{ Name = 'AR clamp (98370 same value)'; Rva = 0x02D06700
            Old = GetBytes-Single ([single]1.7786459); New = $cap }
    )

    # ---- 5.0.15.98370 / 5.0.17.98370 -------------------------------------
    # Table base 0x3BD8090, label slot base 0x2BF2700.
    # Low-end entries 0-3 come from the 98370 documentation
    # (480x360 640x480 800x600 1024x768); only the first 4 are replaced.
    $old98370 = @(
        @{ W = 480;  H = 360; Label = '@UI/480x360'  },
        @{ W = 640;  H = 480; Label = '@UI/640x480'  },
        @{ W = 800;  H = 600; Label = '@UI/800x600'  },
        @{ W = 1024; H = 768; Label = '@UI/1024x768' }
    )
    $sites98370 = New-EntrySites -TblBase 0x3BD8090 -SlotBase 0x2BF2700 -Old $old98370 -New ($UltrawideRes[0..3])
    $sites98370 += @(
        @{ Name = 'AR cap (resolution parse)'; Rva = 0x2BFC1D0
            Old = GetBytes-Single ([single]1.7777778); New = $cap },
        @{ Name = 'quality preset threshold';  Rva = 0x118125E
            Old = (HexToBytes '05'); New = (HexToBytes '07') },
        @{ Name = 'AR clamp (window, key)';    Rva = 0x2C2A588
            Old = GetBytes-Single ([single]1.7886459); New = $cap }
    )

    return @(
        [pscustomobject]@{ Id = '98310'; Version = '5.0.17.98310'; Sites = $sites98310 },
        [pscustomobject]@{ Id = '98370'; Version = '5.0.15/17.98370'; Sites = $sites98370 }
    )
}

function Select-VersionProfile {
    param($Pe)

    $profiles = Get-VersionProfiles
    $best = $null
    $recognizedIncomplete = $null
    foreach ($p in $profiles) {
        $states = Get-SiteStates -Pe $Pe -Sites $p.Sites
        $bad = 0
        $onlyPlaceholders = $true
        for ($i = 0; $i -lt $p.Sites.Count; $i++) {
            if ($states[$i] -ne 'original' -and $states[$i] -ne 'patched') {
                $bad++
                if ($p.Sites[$i].Rva -ne 0) { $onlyPlaceholders = $false }
            }
        }
        if ($bad -eq 0) {
            if ($null -eq $best) { $best = $p }
            elseif ($Pe.Version -like "*$($p.Id)*") { $best = $p }  # if several profiles fully match, prefer the one in the version string
        }
        elseif ($bad -gt 0 -and $onlyPlaceholders) {
            if ($null -eq $recognizedIncomplete) { $recognizedIncomplete = $p }
        }
    }
    if ($null -ne $best) { return $best }
    if ($null -ne $recognizedIncomplete) {
        throw "Version $($Pe.Version) recognized (patch table $($recognizedIncomplete.Id)),`nbut that table is not finished yet (placeholder sites not located); cannot write.`nUpdate to a patch build that supports this version."
    }
    $known = ($profiles | ForEach-Object { $_.Version }) -join ' / '
    throw "The file's bytes do not match any supported version.`n  File version: $($Pe.Version)`n  Supported versions: $known`n  Point -Exe at the correct SC2_x64.exe, or update this patch."
}

# Byte helpers ---------------------------------------------------------------

function GetBytes-U32 { param([uint32]$V) [BitConverter]::GetBytes($V) }
function GetBytes-U64 { param([uint64]$V) [BitConverter]::GetBytes($V) }
function GetBytes-Single { param([single]$V) [BitConverter]::GetBytes($V) }

function HexToBytes {
    param([string]$Hex)
    $clean = $Hex -replace '[^0-9A-Fa-f]', ''
    $out = New-Object byte[] ($clean.Length / 2)
    for ($i = 0; $i -lt $out.Length; $i++) {
        $out[$i] = [Convert]::ToByte($clean.Substring($i * 2, 2), 16)
    }
    return $out
}

# --------------------------------------------------------------------------
# Locate the game
# --------------------------------------------------------------------------

function Get-DocsDir {
    return (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'StarCraft II')
}

function Find-Sc2Exe {
    param([string]$Explicit)

    if ($Explicit) {
        if (-not (Test-Path -LiteralPath $Explicit)) { throw "File not found: $Explicit" }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }
    if ($env:SC2_EXE -and (Test-Path -LiteralPath $env:SC2_EXE)) {
        return (Resolve-Path -LiteralPath $env:SC2_EXE).Path
    }

    # The launch info the game itself writes is the most reliable
    $execInfo = Join-Path (Get-DocsDir) 'ExecuteInfo.txt'
    if (Test-Path -LiteralPath $execInfo) {
        foreach ($line in [System.IO.File]::ReadAllLines($execInfo)) {
            if ($line -match '^\s*executable\s*=\s*(.+?)\s*$') {
                $p = $Matches[1].Trim().Trim('"')
                if (Test-Path -LiteralPath $p) { return $p }
            }
        }
    }

    # Common install roots
    $roots = @(
        'C:\Program Files\StarCraft II',
        'C:\Program Files (x86)\StarCraft II',
        'D:\StarCraft II', 'E:\StarCraft II', 'F:\StarCraft II',
        'D:\Games\StarCraft II', 'E:\Games\StarCraft II', 'F:\Games\StarCraft II',
        'D:\Battle.net\StarCraft II', 'E:\Battle.net\StarCraft II', 'C:\Battle.net\StarCraft II'
    )
    $found = @()
    foreach ($root in $roots) {
        $versions = Join-Path $root 'Versions'
        if (-not (Test-Path -LiteralPath $versions)) { continue }
        foreach ($dir in Get-ChildItem -LiteralPath $versions -Directory -ErrorAction SilentlyContinue) {
            $candidate = Join-Path $dir.FullName 'SC2_x64.exe'
            if (Test-Path -LiteralPath $candidate) {
                $found += [pscustomobject]@{ Build = $dir.Name; Path = $candidate }
            }
        }
    }
    if ($found.Count -gt 0) {
        return ($found | Sort-Object Build | Select-Object -Last 1).Path
    }

    throw "SC2_x64.exe not found. Specify the path with -Exe, e.g.:`n  .\sc2-ultrawide.ps1 status -Exe ""D:\Games\StarCraft II\Versions\Base98370\SC2_x64.exe"""
}

# --------------------------------------------------------------------------
# Minimal PE reader (only for RVA -> file offset)
# --------------------------------------------------------------------------

function Read-PeInfo {
    param([string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { throw "Not a PE file: $Path" }
    $peOff = [BitConverter]::ToInt32($bytes, 0x3C)
    if ([BitConverter]::ToUInt32($bytes, $peOff) -ne 0x00004550) { throw "PE signature missing: $Path" }

    $coff = $peOff + 4
    $nSections = [BitConverter]::ToUInt16($bytes, $coff + 2)
    $optSize = [BitConverter]::ToUInt16($bytes, $coff + 16)
    $opt = $coff + 20
    $magic = [BitConverter]::ToUInt16($bytes, $opt)
    if ($magic -ne 0x20B) { throw "Not a 64-bit PE (PE32+): $Path" }

    $imageBase = [BitConverter]::ToUInt64($bytes, $opt + 24)
    $sections = @()
    $sec = $opt + $optSize
    for ($i = 0; $i -lt $nSections; $i++) {
        $b = $sec + $i * 40
        $name = [System.Text.Encoding]::ASCII.GetString($bytes, $b, 8).TrimEnd([char]0)
        $sections += [pscustomobject]@{
            Name    = $name
            VSize   = [BitConverter]::ToUInt32($bytes, $b + 8)
            VAddr   = [BitConverter]::ToUInt32($bytes, $b + 12)
            RawSize = [BitConverter]::ToUInt32($bytes, $b + 16)
            RawPtr  = [BitConverter]::ToUInt32($bytes, $b + 20)
        }
    }
    return [pscustomobject]@{
        Bytes     = $bytes
        ImageBase = $imageBase
        Sections  = $sections
        Version   = (Get-FileVersion $Path)
    }
}

function Get-FileVersion {
    param([string]$Path)
    try {
        $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
        if ($vi.FileVersion) { return $vi.FileVersion }
        return "$($vi.FileMajorPart).$($vi.FileMinorPart).$($vi.FileBuildPart).$($vi.FilePrivatePart)"
    } catch {
        return 'unknown'
    }
}

function Convert-RvaToOffset {
    param($Pe, [UInt32]$Rva)
    if ($Rva -eq 0) { return -1 }   # placeholder RVA counts as unmapped
    foreach ($s in $Pe.Sections) {
        $span = [Math]::Max($s.VSize, $s.RawSize)
        if ($Rva -ge $s.VAddr -and $Rva -lt ($s.VAddr + $span)) {
            $delta = $Rva - $s.VAddr
            if ($delta -ge $s.RawSize) { return -1 }
            return [int]($s.RawPtr + $delta)
        }
    }
    return -1
}

# --------------------------------------------------------------------------
# Status / patch / revert
# --------------------------------------------------------------------------

function Get-SiteStates {
    param($Pe, $Sites)
    $states = @()
    foreach ($site in $Sites) {
        $off = Convert-RvaToOffset -Pe $Pe -Rva $site.Rva
        if ($off -lt 0) { $states += 'unmapped'; continue }
        $cur = New-Object byte[] $site.Old.Length
        [Array]::Copy($Pe.Bytes, $off, $cur, 0, $site.Old.Length)
        if (Compare-Bytes $cur $site.Old) { $states += 'original' }
        elseif (Compare-Bytes $cur $site.New) { $states += 'patched' }
        else { $states += ('unknown:' + (($cur | ForEach-Object { $_.ToString('X2') }) -join '')) }
    }
    return $states
}

function Compare-Bytes {
    param([byte[]]$A, [byte[]]$B)
    if ($A.Length -ne $B.Length) { return $false }
    for ($i = 0; $i -lt $A.Length; $i++) { if ($A[$i] -ne $B[$i]) { return $false } }
    return $true
}

function Get-ConfigPath {
    param([string]$Explicit)
    if ($Explicit) { return $Explicit }
    return (Join-Path (Get-DocsDir) 'Variables.txt')
}

function Get-DesktopResolution {
    # Return the desktop size the game would see, in real pixels
    # (DPI virtualization would otherwise scale the numbers).
    #   1) DPI-aware WinForms: the primary screen, or the union of all screens
    #      when they tile edge-to-edge (side-by-side multi-monitor virtual
    #      desktop, e.g. two 16:9 panels forming a 5120x1440 32:9 desktop).
    #   2) WMI fallback: first video controller's current desktop mode.
    # Returns a { W; H } object, or $null when detection is impossible.
    try {
        Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public static class Sc2UwDpi {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@ -ErrorAction SilentlyContinue
        [void][Sc2UwDpi]::SetProcessDPIAware()
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $screens = [System.Windows.Forms.Screen]::AllScreens
        if ($screens.Count -gt 0) {
            $r = $screens[0].Bounds
            $area = [long]$r.Width * [long]$r.Height
            foreach ($s in $screens[1..($screens.Count - 1)]) {
                $r = [System.Drawing.Rectangle]::Union($r, $s.Bounds)
                $area += [long]$s.Bounds.Width * [long]$s.Bounds.Height
            }
            # Use the union only when the screens really tile (no overlap,
            # same top edge); otherwise fall back to the primary screen.
            $tiled = ($r.Width * $r.Height -eq $area)
            foreach ($s in $screens) { if ($s.Bounds.Top -ne $r.Top) { $tiled = $false; break } }
            $out = if ($tiled) { $r } else { $screens[0].Bounds }
            if ($out.Width -gt 0 -and $out.Height -gt 0) {
                return [pscustomobject]@{ W = $out.Width; H = $out.Height }
            }
        }
    } catch { }
    try {
        $vc = Get-CimInstance Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.CurrentHorizontalResolution -gt 0 -and $_.CurrentVerticalResolution -gt 0 } |
            Select-Object -First 1
        if ($vc) {
            return [pscustomobject]@{ W = [int]$vc.CurrentHorizontalResolution; H = [int]$vc.CurrentVerticalResolution }
        }
    } catch { }
    return $null
}

# --------------------------------------------------------------------------
# Config writer (Variables.txt)
# --------------------------------------------------------------------------
# Note: variable names here must not collide case-insensitively (PowerShell
# variables are case-insensitive): $newline (the join separator) and
# $updatedLine (the per-line replacement temp) are two different concepts and
# must stay spelled differently.

function Set-GameConfig {
    param([string]$Path, [int]$W, [int]$H, [switch]$WhatIfOnly)

    # Keys the game reads for display/window geometry (windowed fullscreen,
    # borderless):
    #   displaymode=1  ->  windowed fullscreen
    #   width/height   ->  display resolution
    #   windowx/y/width/height -> window geometry
    $wanted = [ordered]@{
        'displaymode'  = '1'
        'width'        = "$W"
        'height'       = "$H"
        'windowx'      = '0'
        'windowy'      = '0'
        'windowwidth'  = "$W"
        'windowheight' = "$H"
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($WhatIfOnly) { Write-Host "[dry-run] would create config: $Path" }
        else {
            $text = ($wanted.Keys | ForEach-Object { "$_=$($wanted[$_])" }) -join "`r`n"
            [System.IO.File]::WriteAllText($Path, $text + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "Created config: $Path"
        }
        return
    }

    $raw = [System.IO.File]::ReadAllText($Path)
    $newline = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
    $lines = $raw -split "`r?`n"
    $seen = @{}
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        $key = ($line -split '=', 2)[0].Trim()
        $lower = $key.ToLowerInvariant()
        if ($wanted.Contains($lower) -and $line.Contains('=')) {
            $updatedLine = "$lower=$($wanted[$lower])"
            $out.Add($updatedLine)
            $seen[$lower] = $true
        } else {
            $out.Add($line)
        }
    }
    foreach ($k in $wanted.Keys) {
        if (-not $seen.ContainsKey($k)) { $out.Add("$k=$($wanted[$k])") }
    }
    while ($out.Count -gt 0 -and $out[$out.Count - 1] -eq '') { $out.RemoveAt($out.Count - 1) }
    $text = ($out -join $newline) + $newline

    if ($WhatIfOnly) {
        Write-Host "[dry-run] would update config: $Path"
        foreach ($line in $out) { if ($line -match '=') { Write-Host "  $line" } }
        return
    }

    $bak = "$Path.sc2uw.bak"
    if (-not (Test-Path -LiteralPath $bak)) {
        [System.IO.File]::Copy($Path, $bak, $true)
        Write-Host "Backed up: $bak"
    }
    [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Config written: $Path"
}

function Invoke-Status {
    param([string]$ExePath, [string]$CfgPath, $Profile, $Sites)

    $pe = Read-PeInfo -Path $ExePath
    Write-Host "Executable : $ExePath"
    Write-Host "Version    : $($pe.Version)"
    if ($Profile) {
        Write-Host ("Patch table: version {0} ({1} sites: {2} ultrawide entries x 4 + 3 constants/thresholds)" -f $Profile.Id, $Profile.Sites.Count, (($Profile.Sites.Count - 3) / 4))
    } else {
        Write-Host 'Patch table: no match (version not supported)' -ForegroundColor Yellow
    }
    Write-Host ("Ultrawide  : " + (($UltrawideRes | ForEach-Object { "$($_.W)x$($_.H)" }) -join '  '))
    Write-Host ("Resolution : {0}x{1}  (aspect {2:F4})  [written to Variables.txt]" -f $Width, $Height, ([double]$Width / [double]$Height))
    Write-Host ("Image base : 0x{0:X}   sections: {1}" -f $pe.ImageBase, $pe.Sections.Count)
    $bak = "$ExePath.sc2uw.bak"
    Write-Host ("Backup     : {0}" -f $(if (Test-Path -LiteralPath $bak) { 'present' } else { 'missing' }))

    if ($Profile) {
        $states = Get-SiteStates -Pe $pe -Sites $Sites
        Write-Host "`nPatch state:"
        for ($i = 0; $i -lt $Sites.Count; $i++) {
            $color = switch ($states[$i]) {
                'patched' { 'Green' }
                'original' { 'Gray' }
                default { 'Red' }
            }
            Write-Host ("  {0,-30} {1}" -f $Sites[$i].Name, $states[$i]) -ForegroundColor $color
        }
    }

    Write-Host "`nConfig: $CfgPath"
    if (Test-Path -LiteralPath $CfgPath) {
        Get-Content -LiteralPath $CfgPath | Where-Object {
            $_ -match '^\s*(displaymode|width|height|windowwidth|windowheight|windowx|windowy)\s*='
        } | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host '  [!] config file missing' -ForegroundColor Yellow
    }

    $running = Get-Process -Name 'SC2_x64' -ErrorAction SilentlyContinue
    Write-Host ("`nGame proc  : {0}" -f $(if ($running) { "running (PID $($running.Id -join ','))" } else { 'not running' }))
}

function Invoke-Apply {
    param([string]$ExePath, [string]$CfgPath, $Sites, [switch]$WhatIfOnly)

    $running = Get-Process -Name 'SC2_x64', 'SC2Switcher_x64', 'SC2' -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host ("[!] Game is running ({0}); cannot write the exe." -f (($running | Select-Object -ExpandProperty Name) -join ', ')) -ForegroundColor Yellow
        Write-Host "    Quit the game and retry, or use: .\sc2-ultrawide.ps1 live" -ForegroundColor Yellow
        return 2
    }

    $pe = Read-PeInfo -Path $ExePath
    Write-Host "Target: $ExePath  (version $($pe.Version))"

    $states = Get-SiteStates -Pe $pe -Sites $Sites
    $unknown = @()
    for ($i = 0; $i -lt $Sites.Count; $i++) {
        if ($states[$i] -like 'unknown*' -or $states[$i] -eq 'unmapped') {
            $unknown += "$($Sites[$i].Name): $($states[$i])"
        }
    }
    if ($unknown.Count -gt 0) {
        Write-Host "`n[!] The file's bytes do not match a supported version; refusing to modify:" -ForegroundColor Red
        $unknown | ForEach-Object { Write-Host "    $_" }
        Write-Host "    File version: $($pe.Version) (this patch supports 5.0.15.98370 / 5.0.17.98370 / 5.0.17.98310)"
        return 3
    }

    if (($states | Where-Object { $_ -ne 'patched' }).Count -eq 0) {
        Write-Host 'Everything is already patched; nothing to do.'
        Set-GameConfig -Path $CfgPath -W $Width -H $Height -WhatIfOnly:$WhatIfOnly
        return 0
    }

    $bak = "$ExePath.sc2uw.bak"
    if (-not (Test-Path -LiteralPath $bak)) {
        if ($WhatIfOnly) { Write-Host "[dry-run] would create backup: $bak" }
        else {
            [System.IO.File]::Copy($ExePath, $bak, $true)
            Write-Host "Backed up: $bak"
        }
    } else {
        Write-Host "Backup already present: $bak"
    }

    Write-Host "`nBytes to write:"
    for ($i = 0; $i -lt $Sites.Count; $i++) {
        if ($states[$i] -ne 'original') { continue }
        $off = Convert-RvaToOffset -Pe $pe -Rva $Sites[$i].Rva
        $oldHex = ($Sites[$i].Old | ForEach-Object { $_.ToString('X2') }) -join ' '
        $newHex = ($Sites[$i].New | ForEach-Object { $_.ToString('X2') }) -join ' '
        Write-Host ("  {0,-30} @0x{1:X8}  {2} -> {3}" -f $Sites[$i].Name, $off, $oldHex, $newHex)
        if (-not $WhatIfOnly) {
            [Array]::Copy($Sites[$i].New, 0, $pe.Bytes, $off, $Sites[$i].New.Length)
        }
    }

    if ($WhatIfOnly) {
        Write-Host "`n[dry-run] no files written"
        Set-GameConfig -Path $CfgPath -W $Width -H $Height -WhatIfOnly
        return 0
    }

    $tmp = "$ExePath.tmp"
    [System.IO.File]::WriteAllBytes($tmp, $pe.Bytes)
    Move-Item -LiteralPath $tmp -Destination $ExePath -Force
    Write-Host "`nWritten: $ExePath" -ForegroundColor Green

    $check = Get-SiteStates -Pe (Read-PeInfo -Path $ExePath) -Sites $Sites
    if (($check | Where-Object { $_ -ne 'patched' }).Count -eq 0) {
        Write-Host 'Read-back check: all patches in effect' -ForegroundColor Green
    } else {
        Write-Host 'Read-back check FAILED!' -ForegroundColor Red
        return 4
    }

    Set-GameConfig -Path $CfgPath -W $Width -H $Height
    return 0
}

function Invoke-Revert {
    param([string]$ExePath, $Sites)

    $bak = "$ExePath.sc2uw.bak"
    if (-not (Test-Path -LiteralPath $bak)) {
        Write-Host "[!] Backup not found: $bak" -ForegroundColor Yellow
        Write-Host '    You can restore the official file with Battle.net Scan & Repair.'
        return 2
    }
    $running = Get-Process -Name 'SC2_x64' -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host '[!] Game is running; quit it first.' -ForegroundColor Yellow
        return 2
    }
    [System.IO.File]::Copy($bak, $ExePath, $true)
    $states = Get-SiteStates -Pe (Read-PeInfo -Path $ExePath) -Sites $Sites
    if (($states | Where-Object { $_ -ne 'original' }).Count -eq 0) {
        Write-Host "Restored to original: $ExePath" -ForegroundColor Green
        return 0
    }
    Write-Host '[!] Bytes after restore do not match the original; use Battle.net Scan & Repair.' -ForegroundColor Red
    return 3
}

# --------------------------------------------------------------------------
# Runtime injection (no game restart)
# --------------------------------------------------------------------------

function Invoke-Live {
    param($Sites, [int]$W, [int]$H)

    $proc = Get-Process -Name 'SC2_x64' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proc) {
        Write-Host '[!] Game is not running. Start it first, or use apply to write permanently.' -ForegroundColor Yellow
        return 2
    }
    $mod = $proc.Modules | Where-Object { $_.ModuleName -eq 'SC2_x64.exe' } | Select-Object -First 1
    if (-not $mod) { Write-Host '[!] module SC2_x64.exe not found' -ForegroundColor Red; return 2 }
    $base = $mod.BaseAddress.ToInt64()

    if (-not ('Sc2UwNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Sc2UwNative {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool WriteProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr written);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool VirtualProtectEx(IntPtr h, IntPtr addr, IntPtr size, uint prot, out uint old);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool VirtualQueryEx(IntPtr h, IntPtr addr, out MEMORY_BASIC_INFORMATION mbi, IntPtr size);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr h);
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORY_BASIC_INFORMATION {
        public IntPtr BaseAddress;
        public IntPtr AllocationBase;
        public uint AllocationProtect;
        public uint __unused;
        public UIntPtr RegionSize;
        public uint State;
        public uint Protect;
        public uint Type;
        public uint __unused2;
    }
}
'@
    }

    $handle = [Sc2UwNative]::OpenProcess(0x1F0FFF, $false, $proc.Id)
    if ($handle -eq [IntPtr]::Zero) {
        Write-Host ('[!] OpenProcess failed, error code ' + [Runtime.InteropServices.Marshal]::GetLastWin32Error()) -ForegroundColor Red
        return 2
    }

    function Read-Mem([int64]$va, [int]$size) {
        $buf = New-Object byte[] $size
        $read = [IntPtr]::Zero
        if (-not [Sc2UwNative]::ReadProcessMemory($handle, [IntPtr]$va, $buf, [IntPtr]$size, [ref]$read)) {
            throw "read of 0x$($va.ToString('X')) failed"
        }
        return $buf
    }
    function Write-Mem([int64]$va, [byte[]]$data) {
        # VirtualProtectEx requires page-aligned address/length: round to the
        # pages spanned by the target
        $page = [int64]([math]::Floor($va / 4096.0)) * 4096
        $span = ([int64]([math]::Ceiling(($va + $data.Length) / 4096.0)) * 4096) - $page
        $old = 0
        [void][Sc2UwNative]::VirtualProtectEx($handle, [IntPtr]$page, [IntPtr]$span, 0x40, [ref]$old)
        $written = [IntPtr]::Zero
        if (-not [Sc2UwNative]::WriteProcessMemory($handle, [IntPtr]$va, $data, [IntPtr]$data.Length, [ref]$written)) {
            $ignored = 0
            [void][Sc2UwNative]::VirtualProtectEx($handle, [IntPtr]$page, [IntPtr]$span, $old, [ref]$ignored)
            throw "write to 0x$($va.ToString('X')) failed"
        }
        $ignored = 0
        [void][Sc2UwNative]::VirtualProtectEx($handle, [IntPtr]$page, [IntPtr]$span, $old, [ref]$ignored)
    }

    # Absolute pointers in memory carry the real load base; relocate them by
    # the base delta
    $delta = $base - 0x140000000

    # Preflight (read-only): pages that are not writable by default must have
    # their protection changed before writing.
    # Probe page by page; abort immediately (zero writes) if any page cannot
    # be made writable, to avoid leaving a half-patched state (the dropdown
    # would have the ultrawide entries while the aspect-ratio constants are
    # still clamped, so selecting one would get clamped back).
    $blocked = @()
    foreach ($site in $Sites) {
        if ($site.Rva -eq 0) { continue }
        $va = $base + $site.Rva
        $page = [int64]([math]::Floor($va / 4096.0)) * 4096
        if ($blocked -contains $page) { continue }
        $mbi = New-Object Sc2UwNative+MEMORY_BASIC_INFORMATION
        $vq = [Sc2UwNative]::VirtualQueryEx($handle, [IntPtr]$page, [ref]$mbi, [IntPtr]([System.Runtime.InteropServices.Marshal]::SizeOf($mbi)))
        if ($vq -and ($mbi.Protect -band 0x4)) { continue }   # already read/write, no probe needed
        $old = 0
        $ok = [Sc2UwNative]::VirtualProtectEx($handle, [IntPtr]$page, [IntPtr]4096, 0x40, [ref]$old)
        if ($ok) {
            $ignored = 0
            [void][Sc2UwNative]::VirtualProtectEx($handle, [IntPtr]$page, [IntPtr]4096, $old, [ref]$ignored)
        }
        if (-not $ok) { $blocked += $page }
    }
    if ($blocked.Count -gt 0) {
        Write-Host ('[!] the following pages are read-only and cannot be made writable (the engine protects its memory constants): ' + ($blocked -join ', ')) -ForegroundColor Red
        Write-Host '[!] The label strings and the aspect-ratio constants sit on read-only pages; full memory injection is not possible on this version (partial injection would only change the dropdown, not the real caps - pointless).' -ForegroundColor Red
        Write-Host '    Use the file patch and restart instead: .\sc2-ultrawide.ps1 apply (quit the game first)' -ForegroundColor Red
        [void][Sc2UwNative]::CloseHandle($handle)
        return 2
    }

    Write-Host ("Process {0} (PID {1})  module base 0x{2:X}" -f $proc.ProcessName, $proc.Id, $base)
    $done = @()
    foreach ($site in $Sites) {
        $old = $site.Old
        $new = $site.New
        if ($old.Length -eq 8) {
            $ov = [BitConverter]::ToUInt64($old, 0)
            $nv = [BitConverter]::ToUInt64($new, 0)
            if ($ov -ge 0x140000000 -and $ov -lt 0x150000000) {
                $old = [BitConverter]::GetBytes([uint64]($ov + $delta))
                $new = [BitConverter]::GetBytes([uint64]($nv + $delta))
            }
        }
        if ($site.Rva -eq 0) { continue }   # skip unlocated sites
        $va = $base + $site.Rva
        $cur = Read-Mem $va $old.Length
        if (Compare-Bytes $cur $new) {
            Write-Host ("  {0,-30} already effective in memory" -f $site.Name) -ForegroundColor DarkGray
            continue
        }
        if (-not (Compare-Bytes $cur $old)) {
            Write-Host ("  {0,-30} bytes do not match, skipping" -f $site.Name) -ForegroundColor Yellow
            continue
        }
        try {
            Write-Mem $va $new
        } catch {
            # Write failed: roll back the original bytes of already-injected
            # sites to keep the process clean, then rethrow
            Write-Host '[!] write failed, rolling back injected sites...' -ForegroundColor Red
            foreach ($d in $done) {
                try { Write-Mem $d.Va $d.Cur } catch { }
            }
            [void][Sc2UwNative]::CloseHandle($handle)
            throw
        }
        $done += [pscustomobject]@{ Va = $va; Cur = $cur }
        Write-Host ("  {0,-30} injected" -f $site.Name) -ForegroundColor Green
    }

    # Make the game recompute the window geometry from the new constants
    $hwnd = $proc.MainWindowHandle
    if ($hwnd -ne [IntPtr]::Zero) {
        $r = New-Object Sc2UwNative+RECT
        [void][Sc2UwNative]::GetWindowRect($hwnd, [ref]$r)
        $curW = $r.Right - $r.Left
        $curH = $r.Bottom - $r.Top
        Write-Host ("`nWindow now: {0}x{1} @ {2},{3}" -f $curW, $curH, $r.Left, $r.Top)
        if ($curW -ne $W -or $curH -ne $H) {
            [void][Sc2UwNative]::SetWindowPos($hwnd, [IntPtr]::Zero, 0, 0, $curW - 1, $curH, 0x20)
            Start-Sleep -Milliseconds 700
            [void][Sc2UwNative]::GetWindowRect($hwnd, [ref]$r)
            Write-Host ("Window after reset: {0}x{1} @ {2},{3}" -f ($r.Right - $r.Left), ($r.Bottom - $r.Top), $r.Left, $r.Top)
        } else {
            Write-Host 'Window size already correct, no reset needed.'
        }
    }
    [void][Sc2UwNative]::CloseHandle($handle)
    return 0
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

if ($Command -eq 'help') {
    Get-Help $PSCommandPath -Detailed
    exit 0
}

# Aliases: keep intuitive commands such as install.bat / restore.bat /
# check.bat working
switch ($Command) {
    'install' { $Command = 'apply' }
    'restore' { $Command = 'revert' }
    'check'   { $Command = 'status' }
}

# Target resolution: auto-detect the primary display so any of the common
# 21:9 / 32:9 ultrawide setups works without -Width/-Height.
if ($Width -eq 0 -or $Height -eq 0) {
    $det = Get-DesktopResolution
    if ($det) {
        $match = $UltrawideRes | Where-Object { $_.W -eq $det.W -and $_.H -eq $det.H } | Select-Object -First 1
        if ($match) {
            $Width = $match.W
            $Height = $match.H
            Write-Host ("Resolution : auto-detected desktop {0}x{1}" -f $Width, $Height) -ForegroundColor Green
        } else {
            $Width = 5120
            $Height = 1440
            Write-Host ("[!] Desktop {0}x{1} is not one of the injected ultrawide resolutions; using 5120x1440. Pass -Width/-Height to override." -f $det.W, $det.H) -ForegroundColor Yellow
        }
    } else {
        $Width = 5120
        $Height = 1440
        Write-Host 'Resolution : could not auto-detect the desktop; using 5120x1440' -ForegroundColor Yellow
    }
}

if ($Width -lt 640 -or $Height -lt 360 -or $Width -gt 16383 -or $Height -gt 16383) {
    Write-Host 'Resolution outside the engine-encodable range (360..16383 per axis).' -ForegroundColor Red
    exit 2
}

$profile = $null
$sites = $null
try {
    $exePath = Find-Sc2Exe -Explicit $Exe
    $cfgPath = Get-ConfigPath -Explicit $Config
    $peInfo = Read-PeInfo -Path $exePath
    $profile = Select-VersionProfile -Pe $peInfo
    $sites = $profile.Sites
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 2
}

switch ($Command) {
    'status' { Invoke-Status -ExePath $exePath -CfgPath $cfgPath -Profile $profile -Sites $sites }
    'apply' { $code = Invoke-Apply -ExePath $exePath -CfgPath $cfgPath -Sites $sites -WhatIfOnly:$DryRun }
    'revert' { $code = Invoke-Revert -ExePath $exePath -Sites $sites }
    'live' { $code = Invoke-Live -Sites $sites -W $Width -H $Height }
}

if ($null -ne $code) { exit $code }
exit 0
