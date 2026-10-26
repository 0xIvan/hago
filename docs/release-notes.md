Fixes for the 0.2.20 changes:

- Ignore in Review always asks first and deletes only the recordings shown, even when AI picked Ignore. Undo still never reaches back past it.
- Stepping away now trims every recording made after your last input, not only the latest one.
- Time spent watching a video or on a call is no longer cut once it ends.
- If saving the away cut fails, Hago tries again instead of keeping the idle time.
- AI runs from older versions that stopped partway can now be undone.
- A failed daily backup is retried after 15 minutes instead of waiting until the next day.

Download the universal DMG, open it and drag Hago to Applications. The app and DMG are Developer ID signed and notarized. Requires macOS 14 or newer; supports Apple Silicon and Intel.

Existing data stays local in the Hago application-support folder. If Accessibility stays unavailable after upgrading from an older locally signed build, remove Hago from the Accessibility / Device Control and Data Access list in System Settings, add `/Applications/Hago.app` again, and enable its switch.
