param(
    [string]$Iscc = "ISCC.exe"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $projectRoot "build/windows/x64/runner/Release"
$installerScript = Join-Path $PSScriptRoot "installer.iss"
$installerExe = Join-Path $projectRoot "build/windows/installer/AstraMusic-Setup-1.1.0.exe"

function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command falló con código $LASTEXITCODE"
    }
}

if (-not (Get-Command $Iscc -ErrorAction SilentlyContinue)) {
    throw "No se encontró ISCC.exe. Agrégalo al PATH o pasa -Iscc con su ruta completa."
}

Push-Location $projectRoot
try {
    Invoke-Checked -Command "flutter" -Arguments @("clean")
    Invoke-Checked -Command "flutter" -Arguments @("pub", "get")
    Invoke-Checked -Command "flutter" -Arguments @("analyze", "--no-pub")
    Invoke-Checked -Command "flutter" -Arguments @("test", "--reporter", "failures-only")
    Invoke-Checked -Command "flutter" -Arguments @("build", "windows", "--release")

    foreach ($required in @("astramusic.exe", "flutter_windows.dll", "data")) {
        if (-not (Test-Path (Join-Path $releaseDir $required))) {
            throw "Falta $required en $releaseDir"
        }
    }

    Invoke-Checked -Command $Iscc -Arguments @($installerScript)
    if (-not (Test-Path $installerExe)) {
        throw "Inno Setup no generó $installerExe"
    }
    Write-Host "Instalador generado: $installerExe"
}
finally {
    Pop-Location
}
