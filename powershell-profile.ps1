#requires -Version 7.0
# PowerShell profile -> $PROFILE.CurrentUserCurrentHost

if (-not [Environment]::UserInteractive) { return }

# ---------------------------------------------------------------------- Encoding
# Native tools (oh-my-posh, git) emit UTF-8. Without this the console decodes
# their bytes as the OEM code page and glyphs turn into mojibake.
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
    [Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
}
catch { }
$OutputEncoding = [System.Text.UTF8Encoding]::new()

# -------------------------------------------------------------------- PSReadLine
Import-Module PSReadLine -ErrorAction SilentlyContinue

# Options before key handlers: -EditMode resets all handlers to its defaults.
Set-PSReadLineOption -EditMode Windows
Set-PSReadLineOption -PredictionSource HistoryAndPlugin
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -HistorySearchCursorMovesToEnd
Set-PSReadLineOption -HistoryNoDuplicates
Set-PSReadLineOption -MaximumHistoryCount 10000
Set-PSReadLineOption -BellStyle None
Set-PSReadLineOption -ShowToolTips

Set-PSReadLineOption -AddToHistoryHandler {
    param([string]$line)
    foreach ($w in 'password', 'secret', 'token', 'apikey', 'api_key',
        'credential', 'connectionstring', 'clientsecret') {
        if ($line -like "*$w*") { return $false }
    }
    return $true
}

Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
Set-PSReadLineKeyHandler -Key 'Ctrl+d'  -Function DeleteCharOrExit
Set-PSReadLineKeyHandler -Key F2        -Function SwitchPredictionView

Set-PSReadLineKeyHandler -Key RightArrow `
    -BriefDescription ForwardCharAndAcceptNextSuggestionWord `
    -LongDescription 'Move right, or accept next suggestion word at end of line' `
    -ScriptBlock {
    param($key, $arg)
    $line = $null; $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    if ($cursor -lt $line.Length) {
        [Microsoft.PowerShell.PSConsoleReadLine]::ForwardChar($key, $arg)
    }
    else {
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptNextSuggestionWord($key, $arg)
    }
}

# ----------------------------------------------------------------------- Modules
foreach ($m in 'Terminal-Icons', 'Microsoft.WinGet.CommandNotFound') {
    if (Get-Module -ListAvailable -Name $m) { Import-Module $m -ErrorAction SilentlyContinue }
}

# -------------------------------------------------------------------- oh-my-posh
$omp = Get-Command oh-my-posh -ErrorAction SilentlyContinue
if ($omp) {
    $theme = Join-Path $PSScriptRoot 'themes\emodipt.omp.json'
    if (-not (Test-Path $theme) -and $env:POSH_THEMES_PATH) {
        $theme = Join-Path $env:POSH_THEMES_PATH 'emodipt.omp.json'
    }

    if (Test-Path $theme) {
        $cache = Join-Path $env:LOCALAPPDATA 'omp-init.ps1'
        $stale = -not (Test-Path $cache) -or
        (Get-Item $cache).LastWriteTime -lt (Get-Item $omp.Source).LastWriteTime -or
        (Get-Item $cache).LastWriteTime -lt (Get-Item $theme).LastWriteTime
        if ($stale) { & $omp.Source init pwsh --config $theme | Out-File $cache -Encoding utf8 }
        . $cache
    }
}

# ------------------------------------------------------------------- Completers
Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    [Console]::InputEncoding = [Console]::OutputEncoding = [System.Text.Utf8Encoding]::new()
    winget complete --word="$($wordToComplete.Replace('"','""'))" `
        --commandline "$($commandAst.ToString().Replace('"','""'))" `
        --position $cursorPosition |
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

# ----------------------------------------------------------------------- Aliases
Set-Alias ll    Get-ChildItem
Set-Alias grep  Select-String
Set-Alias which Get-Command

function .. { Set-Location .. }
function ... { Set-Location ..\.. }

function Edit-Profile {
    $editor = if (Get-Command code-insiders -EA SilentlyContinue) { 'code-insiders' }
    elseif (Get-Command code -EA SilentlyContinue) { 'code' }
    else { 'notepad' }
    & $editor $PROFILE.CurrentUserCurrentHost
}

$global:PROFILE_LOAD_MS = [math]::Round(
    ((Get-Date) - [Diagnostics.Process]::GetCurrentProcess().StartTime).TotalMilliseconds)