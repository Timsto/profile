#requires -Version 7.0
# PowerShell profile -> $PROFILE.CurrentUserCurrentHost
# Set $env:PROFILE_TRACE = 1 and open a new shell for per-section timings.

if (-not [Environment]::UserInteractive) { return }

$__sw  = [Diagnostics.Stopwatch]::StartNew()
$__lap = {
    param($name)
    if ($env:PROFILE_TRACE) {
        Write-Host ('{0,-24} {1,5:N0} ms' -f $name, $__sw.ElapsedMilliseconds) -ForegroundColor DarkGray
    }
    $__sw.Restart()
}

# ---------------------------------------------------------------------- Encoding
# Native tools emit UTF-8. Without this the console decodes their bytes as the
# OEM code page and glyphs turn into mojibake.
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
    [Console]::InputEncoding  = [System.Text.UTF8Encoding]::new()
} catch { }
$OutputEncoding = [System.Text.UTF8Encoding]::new()

& $__lap 'encoding'

# -------------------------------------------------------------------- PSReadLine
Import-Module PSReadLine -ErrorAction SilentlyContinue

# Options before key handlers: -EditMode resets all handlers to its defaults.
Set-PSReadLineOption -EditMode Windows
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -HistorySearchCursorMovesToEnd
Set-PSReadLineOption -HistoryNoDuplicates
Set-PSReadLineOption -MaximumHistoryCount 10000
Set-PSReadLineOption -BellStyle None
Set-PSReadLineOption -ShowToolTips

# Costs ~300 ms. Uncomment for completion-based suggestions on top of history.
# Import-Module CompletionPredictor
# Set-PSReadLineOption -PredictionSource HistoryAndPlugin

Set-PSReadLineOption -AddToHistoryHandler {
    param([string]$line)
    foreach ($w in 'password','secret','token','apikey','api_key',
                   'credential','connectionstring','clientsecret') {
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
        } else {
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptNextSuggestionWord($key, $arg)
        }
    }

& $__lap 'psreadline'

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

& $__lap 'oh-my-posh'

# -------------------------------------------------------------------- Completers
Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    winget complete --word="$($wordToComplete.Replace('"','""'))" `
                    --commandline "$($commandAst.ToString().Replace('"','""'))" `
                    --position $cursorPosition |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}

Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
    param($commandName, $wordToComplete, $cursorPosition)
    dotnet complete --position $cursorPosition "$wordToComplete" |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}

& $__lap 'completers'

# ----------------------------------------------------------------------- Aliases
Set-Alias grep  Select-String
Set-Alias which Get-Command

function ..  { Set-Location .. }
function ... { Set-Location ..\.. }

# Terminal-Icons costs ~1000 ms to import. Loaded on first use instead.
function ll {
    if (-not (Get-Module Terminal-Icons)) { Import-Module Terminal-Icons }
    Get-ChildItem @args
}

function Edit-Profile {
    $editor = if (Get-Command code-insiders -EA SilentlyContinue) { 'code-insiders' }
              elseif (Get-Command code -EA SilentlyContinue)      { 'code' }
              else                                                { 'notepad' }
    & $editor $PROFILE.CurrentUserCurrentHost
}

& $__lap 'aliases'

$global:PROFILE_LOAD_MS = [math]::Round(
    ((Get-Date) - [Diagnostics.Process]::GetCurrentProcess().StartTime).TotalMilliseconds)

Remove-Variable __sw, __lap
