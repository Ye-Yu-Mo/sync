# SFTP Sync Manager

Cross‑platform Flutter app for managing multiple one‑way SFTP sync tasks on macOS and Windows (mobile targets coming soon). It wraps resilient SFTP upload/download logic, task scheduling, conflict handling, and simple UI flows so you no longer need to edit shell scripts by hand.

## Features
- **Server profile**: single shared host/port/credentials plus base directory (default `/data`). Passwords use `flutter_secure_storage` when available and fall back to plaintext config.
- **Task management**: create, edit, toggle, delete, or import/export tasks. Each task tracks local folder, remote subdirectory, FileBrowser user, interval, and last sync time.
- **Relative remote paths**: enter paths relative to `<remoteBase>/<FileBrowser用户>`; either `project/docs` or `/project/docs` is accepted.
- **Real-time & automatic sync**: manual runs show a detailed progress screen. Enabled tasks are auto scheduled—WorkManager on Android/iOS, lightweight timers while the desktop app remains open.
- **Remote user discovery**: task form can scan the remote base directory and list available user folders, so you don’t have to remember every FileBrowser account.

## Getting Started
1. **Configure server**  
   Launch the app → tap the settings icon → fill in host (e.g., `sftp.example.com`), port (`22`), username, password, and remote base (e.g., `/data`). This must be done before creating tasks.
2. **Create a task**  
   - Pick a local directory.  
   - Enter the remote subdirectory relative to the base/user path (e.g., `project/doc` or `/project/doc`). Leave it as `/` to sync directly into the user root.  
   - Provide the FileBrowser user folder (or click “扫描 /data 获取用户” to auto-detect).  
   - Choose a sync interval (minutes) and whether the task is enabled.
3. **Run or monitor**  
   Press “手动同步” for immediate execution. Enabled tasks will auto sync based on the interval whenever the scheduler is running.

## Scheduler Notes
- **Desktop**: The scheduler uses in-process timers. Keep the app running (can be minimized) so timers continue to fire. Full OS background services (LaunchAgent/TaskScheduler) are on the roadmap.
- **Android/iOS**: WorkManager enforces platform minimum intervals (15 minutes on Android). Values lower than the platform minimum will be rounded up when scheduled.
- **Imported tasks**: JSON imports now auto-register their schedules as soon as they are saved—no need to toggle them manually.

## Configuration Files
- macOS app sandbox: `~/Library/Containers/com.example.sftpSyncManager/Data/.sftp_sync/app.json`
- CLI / dev builds: `~/.sftp_sync/app.json`

If you edit configs outside the app, be sure you’re modifying the correct location for the environment you’re testing.

## Development
```bash
flutter pub get
flutter test                # may require write access to Flutter cache
flutter run -d macos        # or windows
```

CI builds (`.github/workflows/build.yml`) produce zipped macOS `.app` bundles and Windows runners, and publish them to GitHub Releases automatically. To run the workflow locally you’ll need `flutter` available and lftp dependencies for the sync scripts if you plan to test shell fallbacks.
