<#
    Windows setup: apps, PowerShell modules, profile, theme.

    Run in an elevated PowerShell:
        irm https://raw.githubusercontent.com/Timsto/profile/main/install.ps1 | iex

    Safe to re-run. Without admin rights, 'machine' scoped packages are skipped.
#>

$ErrorActionPreference = 'Stop'

$RawBase    = 'https://raw.githubusercontent.com/Timsto/profile/main'
$ProfileUrl = "$RawBase/powershell-profile.ps1"
$ThemeUrl   = "$RawBase/themes/emodipt.omp.json"
$ThemeName  = 'emodipt.omp.json'

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

$modules = @(
    'Terminal-Icons'
    'CompletionPredictor'
    'Microsoft.WinGet.Client'
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
function Fail { param($t) Write-Host "   FAIL $t" -ForegroundColor Red }

# --------------------------------------------------------------- Prerequisites
Step 'Prerequisites'

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget not found. Install "App Installer" from the Microsoft Store, then retry.'
}
Ok "winget $((winget --version).Trim())"

$isAdmin = (New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    Ok 'Administrator'
} else {
    Write-Warning 'Not elevated - packages scoped "machine" will be skipped.'
}

$null = winget source update --accept-source-agreements 2>&1

# -------------------------------------------------------------------- Packages
$failed = @()

foreach ($p in $packages) {
    Step $p.Id

    if ($p.Scope -eq 'machine' -and -not $isAdmin) { Skip 'needs admin'; continue }

    $null = winget list --id $p.Id --exact --accept-source-agreements 2>&1
    if ($LASTEXITCODE -eq 0) { Skip 'already installed'; continue }

    $wingetArgs = @(
        'install', '--id', $p.Id, '--exact', '--source', 'winget'
        '--scope', $p.Scope, '--silent'
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
    )
    $out = & winget @wingetArgs 2>&1

    if ($LASTEXITCODE -eq 0) {
        Ok 'installed'
    } else {
        $retry = $wingetArgs | Where-Object { $_ -ne '--scope' -and $_ -ne $p.Scope }
        $null  = & winget @retry 2>&1
        if ($LASTEXITCODE -eq 0) {
            Ok 'installed (no scope)'
        } else {
            Fail "exit code $LASTEXITCODE"
            $out | Select-Object -Last 3 | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkRed }
            $failed += $p.Id
        }
    }
}

# ----------------------------------------------------------------- PowerShell 7
Step 'PowerShell 7'

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
    Fail 'pwsh not found. Close this window, open a new one, run again.'
    return
}

# --------------------------------------------------------------------- Modules
# Always via pwsh 7: CurrentUser scope resolves to a different path in 5.1.
Step 'Modules'

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

# --------------------------------------------------------------------- Profile
Step 'Profile'

$target     = & $pwsh -NoProfile -Command '$PROFILE.CurrentUserCurrentHost'
$profileDir = Split-Path $target -Parent

if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }

try {
    if (Test-Path $target) {
        $backup = "$target.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $target $backup -Force
        Ok "backup: $(Split-Path $backup -Leaf)"
    }
    Invoke-WebRequest -Uri $ProfileUrl -OutFile $target -UseBasicParsing -ErrorAction Stop
    Ok $target
} catch {
    Fail "profile download failed: $($_.Exception.Message)"
    Write-Host "   Manual:  iwr '$ProfileUrl' -OutFile `"$target`"" -ForegroundColor DarkYellow
}

# ----------------------------------------------------------------------- Theme
Step 'Theme'

$themeDir    = Join-Path $profileDir 'themes'
$themeTarget = Join-Path $themeDir $ThemeName

try {
    if (-not (Test-Path $themeDir)) { New-Item -ItemType Directory -Path $themeDir -Force | Out-Null }
    Invoke-WebRequest -Uri $ThemeUrl -OutFile $themeTarget -UseBasicParsing -ErrorAction Stop

    $null = Get-Content -Raw $themeTarget | ConvertFrom-Json
    Ok $themeTarget

    $cache = Join-Path $env:LOCALAPPDATA 'omp-init.ps1'
    if (Test-Path $cache) { Remove-Item $cache -Force }
} catch {
    Fail "theme failed: $($_.Exception.Message)"
    Write-Host '   Profile falls back to $env:POSH_THEMES_PATH.' -ForegroundColor DarkYellow
}

# ------------------------------------------------------------------- Nerd Font
Step 'Nerd Font'

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    $fonts = (New-Object -ComObject Shell.Application).NameSpace(0x14).Items() |
             ForEach-Object { $_.Name }
    if ($fonts -match 'Nerd Font') {
        Skip 'already installed'
    } else {
        oh-my-posh font install CascadiaCode --user
        Ok 'CascadiaCode Nerd Font'
    }
} else {
    Skip 'oh-my-posh not on PATH - restart shell, then: oh-my-posh font install'
}

# ------------------------------------------------------------------------- Git
Step 'Git'

if (Get-Command git -ErrorAction SilentlyContinue) {
    @{
        'init.defaultBranch' = 'main'
        'pull.rebase'        = 'true'
        'core.autocrlf'      = 'true'
        'core.longpaths'     = 'true'
    }.GetEnumerator() | ForEach-Object {
        if (git config --global --get $_.Key 2>$null) {
            Skip $_.Key
        } else {
            git config --global $_.Key $_.Value
            Ok "$($_.Key) = $($_.Value)"
        }
    }
} else {
    Skip 'git not on PATH - restart shell'
}

# ------------------------------------------------------------------------ Done
if ($failed) {
    Write-Host "`nFailed:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host @'

On "Installer hash does not match" the winget manifest lags the download.
Alternatives:
  winget install 9P7KNL5RWT25 -s msstore     # Sysinternals Suite
  winget install 9NKSQGP7F2NH -s msstore     # WhatsApp
  winget install <Id> --ignore-security-hash # non-elevated only

'@ -ForegroundColor DarkYellow
}

Write-Host @"

Done. Open a new Windows Terminal tab (pwsh).

Manual steps:
  Set font face to "CascadiaCode Nerd Font"
  git config --global user.name  "Tim"
  git config --global user.email "..."
  1Password: enable SSH agent
  VS Code Insiders: sign in for Settings Sync

"@ -ForegroundColor Cyan
