# Links every SoulUI* addon folder in this repo into the WoW AddOns folder using directory
# junctions (no admin rights needed). Edits in the repo are then live in game after /reload.
#
#   powershell -ExecutionPolicy Bypass -File tools\link-addons.ps1
#   powershell -ExecutionPolicy Bypass -File tools\link-addons.ps1 -AddOns "D:\Games\World of Warcraft\_retail_\Interface\AddOns"
param(
    [string]$AddOns = "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns"
)

$repo = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path $AddOns)) { throw "AddOns folder not found: $AddOns (pass -AddOns <path>)" }

Get-ChildItem -Path $repo -Directory -Filter "SoulUI*" | ForEach-Object {
    $target = Join-Path $AddOns $_.Name
    if (Test-Path $target) {
        $item = Get-Item $target -Force
        if ($item.LinkType -eq "Junction") {
            Write-Host "ok      $($_.Name) (already linked)"
            return
        }
        Write-Warning "skip    $($_.Name): a real folder already exists at $target - remove it first"
        return
    }
    cmd /c mklink /J "`"$target`"" "`"$($_.FullName)`"" | Out-Null
    Write-Host "linked  $($_.Name) -> $target"
}
