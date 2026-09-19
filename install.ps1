<#
    Windows-Setup: Programme, PowerShell-Module, Profil.

    In einer PowerShell ALS ADMINISTRATOR:
        irm https://raw.githubusercontent.com/Timsto/profile/main/install.ps1 | iex

    Ohne Adminrechte laeuft es auch, ueberspringt dann aber alles mit
    Scope 'machine'. Mehrfach ausfuehrbar - vorhandene Pakete werden
    uebersprungen.
#>

$ErrorActionPreference = 'Stop'

# Downloads am Ende. Muessen auf dieses Repo zeigen.
$RawBase    = 'https://raw.githubusercontent.com/Timsto/profile/main'
$ProfileUrl = "$RawBase/profile.ps1"
$ThemeUrl   = "$RawBase/themes/emodipt.omp.json"
$ThemeName  = 'emodipt.omp.json'

# ---------------------------------------------------------------- Paketliste --
# Scope 'machine' = alle User, braucht Admin. 'user' = nur aktueller User;
# noetig fuer MSIX/Store-Pakete, die kein machine-Scope koennen.
$packages = @(
    @{ Id = 'Microsoft.PowerShell'                ; Scope = 'machine' }
    @{ Id = 'Microsoft.WindowsTerminal'           ; Scope = 'user'    }
    @{ Id = 'Git.Git'                             ; Scope = 'machine' }
    @{ Id = 'Microsoft.VisualStudioCode.Insiders' ; Scope = 'user'    }
    @{ Id = 'AgileBits.1Password'                 ; Scope = 'machine' }
    @{ Id = 'Notion.Notion'                       ; Scope = 'user'    }
    @{ Id = 'Microsoft.PowerToys'                 ; Scope = 'machine' }
    @{ Id = 'Microsoft.Sysinternals.Suite'        ; Scope = 'machine' }
    @{ Id = 'JanDeDobbeleer.OhMyPosh'             ; Scope = 'machine' }
    @{ Id = 'ShareX.ShareX'                       ; Scope = 'machine' }
    @{ Id = 'OBSProject.OBSStudio'                ; Scope = 'machine' }
    @{ Id = 'Devolutions.RemoteDesktopManager'    ; Scope = 'machine' }
    @{ Id = 'RevoUninstaller.RevoUninstaller'     ; Scope = 'machine' }
    @{ Id = 'DeepL.DeepL'                         ; Scope = 'user'    }
    @{ Id = 'WhatsApp.WhatsApp'                   ; Scope = 'user'    }
)

# Bewusst nicht das Meta-Modul Microsoft.Graph: 40+ Submodule, ~600 MB,
# bremst jeden Modul-Autoload. Nur Authentication + die Workloads.
$modules = @(
    'Terminal-Icons'
    'CompletionPredictor'
    'Microsoft.WinGet.Client'
    'Microsoft.WinGet.CommandNotFound'
    'Microsoft.Graph.Authentication'
    'Microsoft.Graph.Identity.DirectoryManagement'
    'Microsoft.Graph.Identity.SignIns'
    'Microsoft.Graph.Identity.Governance'
    'Microsoft.Graph.Users'
    'Microsoft.Graph.Groups'
    'Microsoft.Graph.Applications'
)

function Step { param($t) Write-Host "`n>> $t" -ForegroundColor Cyan }
function Ok   { param($t) Write-Host "   OK   $t" -ForegroundColor Green }
function Skip { param($t) Write-Host "   --   $t" -ForegroundColor DarkGray }
function Fail { param($t) Write-Host "   FEHLER $t" -ForegroundColor Red }

# ------------------------------------------------------------ Voraussetzungen --
Step 'Voraussetzungen'

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget fehlt. Im Microsoft Store "App Installer" installieren, dann erneut.'
}
Ok "winget $((winget --version).Trim())"

$isAdmin = (New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    Ok 'Administrator'
} else {
    Write-Warning 'Keine Adminrechte - Pakete mit Scope "machine" werden uebersprungen.'
}

$null = winget source update --accept-source-agreements 2>&1

# ------------------------------------------------------------------- Pakete --
$failed = @()

foreach ($p in $packages) {
    Step $p.Id

    if ($p.Scope -eq 'machine' -and -not $isAdmin) { Skip 'braucht Admin'; continue }

    $null = winget list --id $p.Id --exact --accept-source-agreements 2>&1
    if ($LASTEXITCODE -eq 0) { Skip 'bereits installiert'; continue }

    $wingetArgs = @(
        'install', '--id', $p.Id, '--exact', '--source', 'winget'
        '--scope', $p.Scope, '--silent'
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
    )
    $out = & winget @wingetArgs 2>&1

    if ($LASTEXITCODE -eq 0) {
        Ok 'installiert'
    } else {
        # 0x8A15002B: kein Installer fuer diesen Scope -> nochmal ohne --scope
        $retry = $wingetArgs | Where-Object { $_ -ne '--scope' -and $_ -ne $p.Scope }
        $null  = & winget @retry 2>&1
        if ($LASTEXITCODE -eq 0) {
            Ok 'installiert (ohne Scope-Vorgabe)'
        } else {
            Fail "Exitcode $LASTEXITCODE"
            $out | Select-Object -Last 3 | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkRed }
            $failed += $p.Id
        }
    }
}

# --------------------------------------------------------------- pwsh finden --
Step 'PowerShell 7'

# PATH neu einlesen - nach frischer Installation kennt die Session pwsh nicht.
$env:Path = @(
    [Environment]::GetEnvironmentVariable('Path','Machine')
    [Environment]::GetEnvironmentVariable('Path','User')
) -join ';'

$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) {
    $pwsh = @("$env:ProgramFiles\PowerShell\7\pwsh.exe") |
            Where-Object { Test-Path $_ } | Select-Object -First 1
}

if ($pwsh) {
    Ok (& $pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')
} else {
    Fail 'pwsh nicht gefunden. Fenster schliessen, neu oeffnen, Skript erneut ausfuehren.'
    return
}

# ------------------------------------------------------------------- Module --
# Immer ueber pwsh 7 installieren. -Scope CurrentUser zeigt in 5.1 und 7 auf
# verschiedene Ordner; aus 5.1 installierte Module waeren in pwsh 7 unsichtbar.
Step 'PowerShell-Module'

foreach ($m in $modules) {
    $have = & $pwsh -NoProfile -Command "[bool](Get-Module -ListAvailable -Name '$m')"
    if ($have -eq 'True') { Skip $m; continue }

    & $pwsh -NoProfile -Command "
        if (Get-Command Install-PSResource -EA SilentlyContinue) {
            Install-PSResource -Name '$m' -Scope CurrentUser -TrustRepository -Quiet
        } else {
            Install-Module -Name '$m' -Scope CurrentUser -Force -AllowClobber
        }"

    if ($LASTEXITCODE -eq 0) { Ok $m } else { Fail $m; $failed += $m }
}

# ------------------------------------------------------------ Profil + Theme --
Step 'Profil'

# Pfad von pwsh selbst erfragen - beruecksichtigt OneDrive-Umleitung von Documents.
$target     = & $pwsh -NoProfile -Command '$PROFILE.CurrentUserCurrentHost'
$profileDir = Split-Path $target -Parent

if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }

try {
    if (Test-Path $target) {
        $backup = "$target.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $target $backup -Force
        Ok "Backup: $(Split-Path $backup -Leaf)"
    }
    # -OutFile statt Invoke-RestMethod: RestMethod wuerde JSON parsen und bei
    # .ps1 je nach Content-Type Ueberraschungen liefern.
    Invoke-WebRequest -Uri $ProfileUrl -OutFile $target -UseBasicParsing -ErrorAction Stop
    Ok $target
} catch {
    Fail "Profil-Download fehlgeschlagen: $($_.Exception.Message)"
    Write-Host "   Manuell:  iwr '$ProfileUrl' -OutFile `"$target`"" -ForegroundColor DarkYellow
}

Step 'oh-my-posh Theme'

# Neben das Profil, nicht in POSH_THEMES_PATH: der Pfad aendert sich bei jedem
# oh-my-posh-Update und der Ordner wird dabei ueberschrieben.
$themeDir    = Join-Path $profileDir 'themes'
$themeTarget = Join-Path $themeDir $ThemeName

try {
    if (-not (Test-Path $themeDir)) { New-Item -ItemType Directory -Path $themeDir -Force | Out-Null }
    Invoke-WebRequest -Uri $ThemeUrl -OutFile $themeTarget -UseBasicParsing -ErrorAction Stop

    # Kaputtes JSON faellt sonst erst beim naechsten Shell-Start auf.
    $null = Get-Content -Raw $themeTarget | ConvertFrom-Json
    Ok $themeTarget

    # Init-Cache verwerfen, sonst rendert das Profil weiter das alte Theme.
    $cache = Join-Path $env:LOCALAPPDATA 'omp-init.ps1'
    if (Test-Path $cache) { Remove-Item $cache -Force }
} catch {
    Fail "Theme fehlgeschlagen: $($_.Exception.Message)"
    Write-Host '   Profil faellt auf $env:POSH_THEMES_PATH zurueck.' -ForegroundColor DarkYellow
}

# ---------------------------------------------------------------- Nerd Font --
Step 'Nerd Font'

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    $fonts = (New-Object -ComObject Shell.Application).NameSpace(0x14).Items() |
             ForEach-Object { $_.Name }
    if ($fonts -match 'Nerd Font') {
        Skip 'bereits vorhanden'
    } else {
        oh-my-posh font install CascadiaCode --user
        Ok 'CascadiaCode Nerd Font'
    }
} else {
    Skip 'oh-my-posh nicht im PATH - Shell neu starten, dann: oh-my-posh font install'
}

# ----------------------------------------------------------------- Git-Basics --
Step 'Git'

if (Get-Command git -ErrorAction SilentlyContinue) {
    @{
        'init.defaultBranch' = 'main'
        'pull.rebase'        = 'true'
        'core.autocrlf'      = 'true'
        'core.longpaths'     = 'true'
    }.GetEnumerator() | ForEach-Object {
        if (git config --global --get $_.Key 2>$null) {
            Skip "$($_.Key)"
        } else {
            git config --global $_.Key $_.Value
            Ok "$($_.Key) = $($_.Value)"
        }
    }
} else {
    Skip 'git nicht im PATH - Shell neu starten'
}

# ---------------------------------------------------------------------- Ende --
if ($failed) {
    Write-Host "`nFehlgeschlagen:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host @'

Bei "Installer hash does not match" hinkt das winget-Manifest dem Download
hinterher - betrifft oefter DeepL und Sysinternals. Alternativen:
  winget install 9P7KNL5RWT25 -s msstore     # Sysinternals Suite
  winget install 9NKSQGP7F2NH -s msstore     # WhatsApp
  winget install <Id> --ignore-security-hash # geht nur OHNE Admin

'@ -ForegroundColor DarkYellow
}

Write-Host @"

Fertig. Neues Windows Terminal oeffnen (pwsh-Profil).

Noch von Hand:
  Font face auf "CascadiaCode Nerd Font" setzen
  git config --global user.name  "Tim"
  git config --global user.email "..."
  1Password: SSH-Agent aktivieren
  VS Code Insiders: Settings Sync anmelden

"@ -ForegroundColor Cyan
