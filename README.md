# CC News App

Flutter Android/iOS WebView shell for [CC News](https://cc-news.netlify.app/). The website supplies the app experience; Flutter provides native edge-to-edge system bars, WebView navigation, permissions, and file selection.

## Run

```powershell
flutter pub get
flutter run
```

Android Back follows web navigation history. At the home page it stays in the app. Camera and microphone prompts are requested only when the site starts camera or video capture; location is requested only when the map asks for it. Android file uploads use the system file picker.

## Build Android Debug APK

```powershell
flutter build apk --debug
```

The APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.

iOS builds require macOS with Xcode installed.