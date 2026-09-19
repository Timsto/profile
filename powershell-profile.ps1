#requires -Version 7.0
<#
    PowerShell-Profil
    Deployed von 02-terminal.ps1 nach $PROFILE.CurrentUserCurrentHost

    Reihenfolge ist Absicht:
      1. PSReadLine-OPTIONEN (inkl. EditMode) zuerst
      2. danach erst die Keybindings
    Grund: Set-PSReadLineOption -EditMode setzt alle Keybindings auf die
    Defaults des Modus zurueck. Standen die Handler davor, waren sie weg.
#>

# ----------------------------------------------------------- Nicht-interaktiv --
# Bei Remoting, VS Code Tasks, CI usw. das Profil frueh verlassen -
# spart Startzeit und verhindert Fehler in Sessions ohne Konsole.
if (-not [Environment]::UserInteractive) { return }

# --------------------------------------------------------------- PSReadLine --
Import-Module PSReadLine -ErrorAction SilentlyContinue

# --- Optionen ZUERST (EditMode resettet sonst die Keybindings unten) ---
Set-PSReadLineOption -EditMode Windows
Set-PSReadLineOption -PredictionSource HistoryAndPlugin   # History + CompletionPredictor
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -HistorySearchCursorMovesToEnd       # fehlte bisher
Set-PSReadLineOption -HistoryNoDuplicates
Set-PSReadLineOption -MaximumHistoryCount 10000
Set-PSReadLineOption -BellStyle None
Set-PSReadLineOption -ShowToolTips

# Keine Secrets in der History speichern
Set-PSReadLineOption -AddToHistoryHandler {
    param([string]$line)
    $sensitive = 'password', 'secret', 'token', 'apikey', 'api_key',
                 'credential', 'connectionstring', 'clientsecret'
    foreach ($word in $sensitive) {
        if ($line -like "*$word*") { return $false }
    }
    return $true
}

# --- Keybindings NACH den Optionen ---
Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
Set-PSReadLineKeyHandler -Key 'Ctrl+d'  -Function DeleteCharOrExit
Set-PSReadLineKeyHandler -Key F2        -Function SwitchPredictionView

# RightArrow: am Zeilenende das naechste Wort des Vorschlags uebernehmen,
# sonst normal ein Zeichen nach rechts.
Set-PSReadLineKeyHandler -Key RightArrow `
    -BriefDescription ForwardCharAndAcceptNextSuggestionWord `
    -LongDescription 'Zeichen nach rechts, am Zeilenende naechstes Vorschlagswort uebernehmen' `
    -ScriptBlock {
        param($key, $arg)
        $line = $null; $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
        if ($cursor -lt $line.Length) {
            [Microsoft.PowerShell.PSConsoleReadLine]::ForwardChar($key, $arg)
        } else {
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptNextSuggestionWord($key, $arg)
        }
    }

# Ersatz fuer den alten F7/Out-GridView-Block: Out-GridView gibt es in PS7 nicht.
# Braucht Microsoft.PowerShell.ConsoleGuiTools (optional).
Set-PSReadLineKeyHandler -Key F7 `
    -BriefDescription HistoryPicker `
    -LongDescription 'History durchsuchen und Befehl einfuegen' `
    -ScriptBlock {
        if (-not (Get-Module -ListAvailable Microsoft.PowerShell.ConsoleGuiTools)) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert(
                '# Install-PSResource Microsoft.PowerShell.ConsoleGuiTools')
            return
        }
        $pick = Get-Content (Get-PSReadLineOption).HistorySavePath |
                Select-Object -Unique |
                Out-ConsoleGridView -Title 'History' -OutputMode Single
        if ($pick) {
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($pick)
        }
    }

# ------------------------------------------------------------------- Module --
# Nur laden, was wirklich da ist - sonst roter Fehler bei jedem Shell-Start.
# posh-git ist bewusst raus: oh-my-posh macht den Git-Status selbst.
foreach ($mod in 'Terminal-Icons', 'Microsoft.WinGet.CommandNotFound') {
    if (Get-Module -ListAvailable -Name $mod) {
        Import-Module $mod -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------- oh-my-posh --
# Der Init-Output wird gecacht. Spart pro Shell-Start einen Prozessstart
# (~150-250 ms). Cache wird neu erzeugt, wenn exe oder Theme neuer sind.
$ompCommand = Get-Command oh-my-posh -ErrorAction SilentlyContinue
if ($ompCommand) {

    # Theme bevorzugt aus dem Profilverzeichnis (portabel), sonst Fallback.
    $themeName = 'emodipt.omp.json'
    $themePath = Join-Path $PSScriptRoot "themes\$themeName"
    if (-not (Test-Path $themePath) -and $env:POSH_THEMES_PATH) {
        $themePath = Join-Path $env:POSH_THEMES_PATH $themeName
    }

    if (Test-Path $themePath) {
        $ompCache = Join-Path $env:LOCALAPPDATA 'omp-init.ps1'

        $needsRebuild = $true
        if (Test-Path $ompCache) {
            $cacheTime = (Get-Item $ompCache).LastWriteTime
            $needsRebuild = ($cacheTime -lt (Get-Item $ompCommand.Source).LastWriteTime) -or
                            ($cacheTime -lt (Get-Item $themePath).LastWriteTime)
        }

        if ($needsRebuild) {
            & $ompCommand.Source init pwsh --config $themePath | Out-File $ompCache -Encoding utf8
        }

        . $ompCache
    }
}

# -------------------------------------------------------- Argument Completer --
Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    [Console]::InputEncoding = [Console]::OutputEncoding = [System.Text.Utf8Encoding]::new()
    $word = $wordToComplete.Replace('"', '""')
    $ast  = $commandAst.ToString().Replace('"', '""')
    winget complete --word="$word" --commandline "$ast" --position $cursorPosition |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}

if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
        param($commandName, $wordToComplete, $cursorPosition)
        dotnet complete --position $cursorPosition "$wordToComplete" |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
    }
}

if (Get-Command gh -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName gh -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $env:COMP_LINE  = $commandAst.ToString()
        $env:COMP_POINT = $cursorPosition
        gh completion -s powershell | Out-String | Invoke-Expression
    }
}

# ------------------------------------------------------------------ Aliases --
Set-Alias -Name ll   -Value Get-ChildItem
Set-Alias -Name grep -Value Select-String
Set-Alias -Name which -Value Get-Command

function .. { Set-Location .. }
function ... { Set-Location ..\.. }

function Reload-Profile {
    . $PROFILE.CurrentUserCurrentHost
    Write-Host 'Profil neu geladen.' -ForegroundColor Green
}

function Edit-Profile {
    $editor = if (Get-Command code-insiders -EA SilentlyContinue) { 'code-insiders' }
              elseif (Get-Command code -EA SilentlyContinue)      { 'code' }
              else                                                { 'notepad' }
    & $editor $PROFILE.CurrentUserCurrentHost
}

# -------------------------------------------------------- Startzeit-Messung --
# Zum Debuggen: in der Shell  $PROFILE_LOAD_MS  abfragen.
$global:PROFILE_LOAD_MS = [math]::Round(
    ((Get-Date) - [System.Diagnostics.Process]::GetCurrentProcess().StartTime).TotalMilliseconds)
