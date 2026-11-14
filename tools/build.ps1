param(
    [string]$Godot = "C:/Users/bobde/AppData/Local/Programs/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe",
    [string]$JavaHome = "C:/Program Files/JetBrains/JetBrains Rider 2026.1.4/jbr",
    [ValidateSet("All", "Windows", "Android")][string]$Target = "All"
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not (Test-Path -LiteralPath $Godot)) { throw "Pass -Godot with the Godot 4.7.2 console executable." }
Push-Location $projectRoot
try {
    New-Item -ItemType Directory -Force -Path "builds/windows", "builds/android" | Out-Null
    if (-not (Test-Path -LiteralPath "builds/.gdignore")) { New-Item -ItemType File -Path "builds/.gdignore" | Out-Null }
    & $Godot --headless --path $projectRoot --editor --import --quit
    if ($LASTEXITCODE -ne 0) { throw "Godot import failed." }
    if ($Target -in @("All", "Windows")) {
        & $Godot --headless --path $projectRoot --export-release "Windows Desktop" "builds/windows/Furry Sudoku.exe"
        if ($LASTEXITCODE -ne 0) { throw "Windows export failed." }
    }
    if ($Target -in @("All", "Android")) {
        $keytool = Join-Path $JavaHome "bin/keytool.exe"
        if (-not (Test-Path -LiteralPath $keytool)) { throw "Pass -JavaHome with a JDK directory." }
        New-Item -ItemType Directory -Force -Path ".signing" | Out-Null
        $signingFile = Join-Path $projectRoot ".signing/android.json"
        $keystore = Join-Path $projectRoot ".signing/furry-sudoku.keystore"
        if (-not (Test-Path -LiteralPath $signingFile)) {
            if (Test-Path -LiteralPath $keystore) { throw "Existing signing key found without its configuration; preserve the key and restore android.json." }
            $signing = @{ alias = "furry-sudoku"; password = [Guid]::NewGuid().ToString("N") }
            $env:FURRY_KEY_PASSWORD = $signing.password
            & $keytool -genkeypair -keystore $keystore -storepass:env FURRY_KEY_PASSWORD -keypass:env FURRY_KEY_PASSWORD -alias $signing.alias -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Furry Sudoku" -noprompt
            if ($LASTEXITCODE -ne 0) { throw "Signing key creation failed." }
            $signing | ConvertTo-Json | Set-Content -LiteralPath $signingFile
        }
        $signing = Get-Content -Raw -LiteralPath $signingFile | ConvertFrom-Json
        $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $keystore
        $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $signing.alias
        $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $signing.password
        & $Godot --headless --path $projectRoot --export-release "Android" "builds/android/Furry Sudoku.apk"
        if ($LASTEXITCODE -ne 0) { throw "Android export failed." }
    }
} finally {
    Remove-Item Env:FURRY_KEY_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:GODOT_ANDROID_KEYSTORE_RELEASE_USER -ErrorAction SilentlyContinue
    Remove-Item Env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD -ErrorAction SilentlyContinue
    Pop-Location
}
