- Added **Hago → Check for Updates…** below Settings in the app menu.
- Remembered Accessibility permission requests across launches to avoid repeated macOS prompts.
- Stopped attempting Accessibility window-title reads while access is unavailable.

Download the universal DMG, open it and drag Hago to Applications. The app and DMG are Developer ID signed and notarized. Requires macOS 14 or newer; supports Apple Silicon and Intel.

Existing data stays local in the Hago application-support folder. If Accessibility stays unavailable after upgrading from an older locally signed build, remove Hago from the Accessibility / Device Control and Data Access list in System Settings, add `/Applications/Hago.app` again, and enable its switch.
