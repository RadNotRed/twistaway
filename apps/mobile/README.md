# MotoPlanner Mobile

Flutter mobile app for MotoPlanner. It targets Android, iOS, web testing, and Windows desktop during local development.

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d web-server
```

The app shell currently includes:

- Material 3 light, dark, and system theme modes.
- Motorcycle route preference controls.
- Voice prompt preview for directions.
- OpenStreetMap map tiles for development.
- Nominatim location search.
- OSRM demo routing with route geometry, distance, duration, and turn cards.
- A vault crypto helper for password-derived encrypted payloads.
- Generated Android, iOS, web, and Windows platform folders.

Android testing requires Android Studio or an Android SDK. iOS device/simulator testing requires macOS and Xcode.

The current map/search/routing providers are good for local development and early product feel. Before production, replace them with provider accounts or hosted services that match expected traffic, caching, attribution, and offline-map requirements.
