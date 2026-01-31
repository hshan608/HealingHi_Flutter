# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HealingHi is a Flutter-based mobile application for displaying, searching, and managing inspirational quotes. The app uses Supabase as its backend for data storage and user management, with device-based user identification.

## Development Commands

### Setup
```bash
# Install dependencies
flutter pub get

# Load environment variables (ensure .env file exists with Supabase credentials)
# Required variables: SUPABASE_URL, SUPABASE_ANON_KEY

# Generate app icons
flutter pub run flutter_launcher_icons
```

### Running the App
```bash
# Run in debug mode (default device)
flutter run

# Run on specific device
flutter devices  # List available devices
flutter run -d <device-id>

# Run with specific flavor/mode
flutter run --release  # Release mode
flutter run --profile  # Profile mode for performance testing
```

### Testing
```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/widget_test.dart

# Run tests with coverage
flutter test --coverage
```

### Code Quality
```bash
# Analyze code for issues
flutter analyze

# Format code
flutter format lib/

# Check for formatting issues without modifying
flutter format --set-exit-if-changed lib/
```

### Building
```bash
# Build APK (Android)
flutter build apk

# Build App Bundle (Android)
flutter build appbundle

# Build iOS (requires macOS)
flutter build ios

# Build for Windows
flutter build windows
```

## Architecture

### Single-File Architecture
This project uses a **single-file architecture** where all code resides in `lib/main.dart`. All screens, widgets, and business logic are defined in this one file:
- `HomeScreen`: Main feed displaying quotes from Supabase
- `SearchScreen`: Search functionality with filters (author, content, subject/tag)
- `BookmarkScreen`: Saved/bookmarked quotes
- `MyPageScreen`: User profile with image upload, language settings, and share progress

### State Management
The app uses **StatefulWidget** and `setState()` for state management. Each screen maintains its own local state without external state management libraries.

### Data Layer

**Supabase Integration:**
- Backend service for all data operations
- Global client initialized at app startup: `final supabase = Supabase.instance.client`
- Environment variables loaded from `.env` file using `flutter_dotenv`

**Database Tables:**
- `quotes`: Stores quote data with fields like `id`, `text_kr`, `resoner_kr` (author), `tag_kr` (subject), `created_at`
- `users`: User profiles with `idx` (primary key), `device_id` (unique), `user_id` (name), `profile_image_url`, `language`
- `users_quotes`: Junction table linking users to saved quotes via `user_idx` and `quotes_id`

**Supabase Storage:**
- `avatars` bucket: Stores user profile images at path `profiles/{device_id}.{ext}`

### User Identification
The app uses **device-based identification** rather than traditional authentication:
- Device ID is extracted using `device_info_plus` package
- Different platforms use different identifiers (Android: `androidInfo.id`, iOS: `identifierForVendor`, Windows: `deviceId`, etc.)
- Users are automatically created/retrieved based on device ID
- No login/signup flow required

### Asset Management
- All assets stored in `assets/` directory
- Custom icons for navigation (e.g., `quotes1.png`, `heart1.png`, `heart2.png`)
- Images displayed for empty states (`sorry.png`)
- Assets declared in `pubspec.yaml` under `flutter.assets`

## Key Patterns

### Quote ID Handling
Quotes may have either `id` or `idx` fields. Use the helper pattern:
```dart
String? _extractQuoteId(Map<String, dynamic> quote) {
  final value = quote['id'] ?? quote['idx'];
  if (value == null) return null;
  return value.toString();
}
```

### Safe Type Conversion
Convert dynamic values to int safely:
```dart
int? _toInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}
```

### Mounted Checks
Always check `mounted` before calling `setState()` or showing SnackBars in async callbacks to prevent errors after widget disposal.

### Share Functionality
The app implements a fallback pattern for sharing:
1. Attempt native share using `share_plus` package
2. If share fails, copy to clipboard using `Clipboard.setData()`
3. Show user feedback via SnackBar

### Bookmark Toggle Pattern
Bookmarking uses an optimistic UI pattern:
1. Check if already saved via local state (`_savedQuoteIds` Set)
2. Delete from `users_quotes` if saved, or upsert if not
3. Update local state and show feedback
4. Handle errors gracefully with user-friendly messages

## Dependencies

**Core:**
- `flutter`: Framework
- `supabase_flutter: ^2.8.2`: Backend integration
- `flutter_dotenv: ^5.1.0`: Environment variable management

**Features:**
- `share_plus: ^10.1.2`: Native sharing
- `image_picker: ^1.1.2`: Profile image selection
- `device_info_plus: ^10.1.2`: Device identification

**Development:**
- `flutter_test`: Testing framework
- `flutter_lints: ^5.0.0`: Linting rules
- `flutter_launcher_icons: ^0.14.1`: Icon generation

## Environment Variables

Create a `.env` file in the project root with:
```
SUPABASE_URL=your_supabase_project_url
SUPABASE_ANON_KEY=your_supabase_anon_key
```

**IMPORTANT:** Never commit `.env` file to version control (already in `.gitignore`).

## Common Development Scenarios

### Adding New Fields to Quotes
1. Update Supabase `quotes` table schema
2. Modify quote display widgets (`_buildContentBox`, `_buildBookmarkCard`)
3. Update search logic in `SearchScreen` if searchable

### Modifying User Profile Fields
1. Update `users` table in Supabase
2. Modify `MyPageScreen` state variables
3. Update `_loadUserData()` and save methods (`_saveUserToSupabase`, `_updateLanguage`)

### Adding New Screens
1. Create new `StatefulWidget` class in `main.dart`
2. Add screen to `_screens` list in `MainScreen._MainScreenState`
3. Add corresponding `BottomNavigationBarItem`

### Debugging Device ID Issues
If users can't save quotes or profile:
- Check device ID extraction logic in `_initUserIdentity()`
- Verify `users` table has `device_id` unique constraint
- Test on actual devices (emulators may have inconsistent device IDs)

## Platform-Specific Notes

- **Android**: Requires `android:minSdkVersion 21` (specified in launcher icons config)
- **iOS**: Uses `identifierForVendor` which resets on app uninstall
- **Windows/Linux/macOS**: Supported but less tested; device ID mechanisms vary
- **Web**: Configured for icon generation but device ID may not work as expected
