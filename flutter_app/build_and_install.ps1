# Build and install Flutter APK on connected Android device
# Usage: run from d:\workspace\cv_project\flutter_app

param(
    [string]$Mode = "release"
)

Write-Host "Starting build_and_install.ps1 (Mode=$Mode)"

# Ensure flutter is available
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
  Write-Error "`nFlutter not found in PATH. Install Flutter and add to PATH.`n"
  exit 1
}

# Ensure adb is available
$adb = Get-Command adb -ErrorAction SilentlyContinue
if (-not $adb) {
  Write-Warning "adb not found in PATH. You can still run 'flutter install' if flutter finds the device."
}

# Run pub get
Write-Host "Running flutter pub get..."
flutter pub get
if ($LASTEXITCODE -ne 0) {
  Write-Warning "flutter pub get failed. Continuing anyway."
}

# Try release build first
if ($Mode -eq 'release') {
  Write-Host "Building release APK..."
  flutter build apk --release
  if ($LASTEXITCODE -eq 0) {
    # try to find built APK
    $candidates = Get-ChildItem -Path "build" -Filter "*.apk" -Recurse | Sort-Object LastWriteTime -Descending
    if ($candidates.Count -gt 0) {
      $apk = $candidates[0].FullName
      Write-Host "Found APK: $apk"
      if ($adb) {
        Write-Host "Installing APK on device..."
        adb install -r $apk
        if ($LASTEXITCODE -eq 0) {
          Write-Host "APK installed successfully."
          exit 0
        } else {
          Write-Warning "adb install failed. You can install the APK manually: $apk"
          exit 1
        }
      } else {
        Write-Host "adb not found. APK available at: $apk"
        exit 0
      }
    } else {
      Write-Warning "Release build succeeded but APK not found in build output."
    }
  } else {
    Write-Warning "Release build failed; will try flutter install (debug) as fallback."
  }
}

# Fallback: flutter install (uses debug build) which also installs to attached device
Write-Host "Running flutter install (debug) as fallback..."
flutter install
if ($LASTEXITCODE -eq 0) {
  Write-Host "App installed via flutter install."
  exit 0
} else {
  Write-Error "flutter install failed. Connect device and ensure adb works, or install APK manually if build artifacts exist."
  exit 1
}
