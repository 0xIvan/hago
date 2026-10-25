- Rules now say what they cover in plain words. Pick an App, a Website or a Page instead of choosing between app names, bundle IDs, hosts, URLs and match operators.
- Choose apps from a list of the apps you actually use, with icons and tracked time. Website suggestions come from your history, and pasted links are trimmed to the site.
- Narrow an app or website rule to windows whose title contains or matches a phrase, for example only Discord windows with "#work" in the title.
- The editor shows how many past recordings a rule matches before you save it, and updates all history by default. Manual corrections stay as they are.
- The priority number is gone. When several rules match, the most specific one wins: a page beats a window title, and a title beats a whole website or app.
- Rules, Privacy, Review "Always…" choices, the Activity inspector and AI suggestions all describe rules the same way, such as "Everything in Slack" or "All of github.com and its subdomains".
- Advanced matching (app name, address patterns, regular expressions) is still available from Advanced… for rules that need it. Existing rules keep working unchanged.

Download the universal DMG, open it and drag Hago to Applications. The app and DMG are Developer ID signed and notarized. Requires macOS 14 or newer; supports Apple Silicon and Intel.

Existing data stays local in the Hago application-support folder. If Accessibility stays unavailable after upgrading from an older locally signed build, remove Hago from the Accessibility / Device Control and Data Access list in System Settings, add `/Applications/Hago.app` again, and enable its switch.
