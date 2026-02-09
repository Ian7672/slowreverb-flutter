# SlowReverb

SlowReverb is a cross-platform Flutter utility to slow down song tempo, maintain pitch stability, and add a chain of reverb/echo effects similar to chill remix productions. The application utilizes FFmpeg along with a real-time native bridge (Android) to make batch processing more efficient.

## Main Features
- Drag-and-drop dropzone + file queue with estimated output size.
- Automatic/manual tempo settings and customizable reverb character presets.
- Real-time preview (Android) or FFmpeg preview on other platforms.
- Output folder management, FFmpeg path settings, and parallel workers for fast batch processing.
- Settings panel with donation links (Trakteer/Ko-fi), GitHub/icon credits, and permanent language and light/dark theme toggles.
- Help button (question mark icon) with a multilingual explanation dialog that follows the device’s `Locale`.

## Help Button
In the top-right corner, there is a question mark icon. When clicked, a dialog appears explaining the technical architecture and each menu (Dropzone, Tempo, Reverb, Preview, Output/FFmpeg, Batch). The dialog detects the device's language; Indonesian and English content are available, while other languages automatically fall back to English, making it ready for expansion.

## Settings, Donations, and Mode
Tap the gear icon to open the settings panel. From there you can:

- Direct users to support channels (`https://trakteer.id/Ian7672` and `https://ko-fi.com/Ian7672`).
- Remind users of the GitHub project credit `Ian7672` and the Flaticon icon source.
- Permanently lock the UI language and light/dark mode without following the system.

The settings panel saves these preferences using `SharedPreferences`, so the user's choices will reappear when the application is reopened.

## Icon Placeholder
<img src="https://raw.githubusercontent.com/Ian7672/slowreverb-flutter/main/assets/icon/icon.png" width="128" alt="FadeTail Icon">

## Project Attribution & License
- Icon source: Flaticon – [Slow Down](https://www.flaticon.com/free-icon/slow-down_2326176?term=slowed+music&page=1&position=35&origin=search&related_id=2326176). Follow Flaticon’s license rules (usually requiring attribution with a link and creator's name) when using the icon.
- Project credit: Include a reference such as `SlowReverb by <your name> (https://github.com/<repo>)` in publications, derivative applications, or promotional materials. If you redistribute the project or use it in other products, include both the icon and project credits side by side.

## Running the Project
1. Ensure Flutter 3.8 or newer is installed.
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the application:
   ```bash
   flutter run
   ```