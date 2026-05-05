# Flutter Speed App (prototype)

This minimal Flutter app streams camera frames (JPEG) to a Python backend WebSocket and displays object IDs and speeds returned by the server.

Notes:
- For emulator use `ws://10.0.2.2:8000/ws` (Android emulator).
- For a device on the same LAN, use `ws://<HOST_IP>:8000/ws` where HOST_IP is your PC IP.
- This prototype uses `CameraController.takePicture()` at an interval for simplicity. For better performance use `startImageStream()` and native conversion to JPEG.

Run:

```bash
cd flutter_app
flutter pub get
flutter run
```

Android permissions (add to `android/app/src/main/AndroidManifest.xml`):

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

iOS (Info.plist): add `NSCameraUsageDescription`.

## Build & Install APK (Windows)

This repository includes a helper PowerShell script to build an APK and install it on a connected Android device.

Requirements:
- Flutter installed and on PATH
- Android SDK + `adb` on PATH
- A device connected with USB debugging enabled

Run from project root:

```powershell
cd flutter_app
.\build_and_install.ps1
```

The script will run `flutter pub get`, attempt a release build, then install the APK with `adb install -r`. If the release build fails it will fall back to `flutter install`.

Notes on connectivity:
- For devices connected to the same LAN as your PC, update the WebSocket server address in the app UI to `ws://<PC_IP>:8000/ws`.
- Alternatively use `adb reverse tcp:8000 tcp:8000` and keep the app using `ws://localhost:8000/ws`.
- Ensure the backend is running and Windows Firewall allows incoming connections to port 8000 or allow `python.exe`.
