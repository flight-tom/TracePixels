## Install

1. Open the `.dmg` and drag **TracePixels** into **Applications**.
2. TracePixels is signed ad hoc and **not notarized by Apple**, so macOS blocks it the first time. Try to open it once, then go to **System Settings › Privacy & Security**, scroll down and click **Open Anyway**. Alternatively, remove the quarantine flag in Terminal:

   ```bash
   xattr -dr com.apple.quarantine /Applications/TracePixels.app
   ```

3. Press **⌃⇧4** to capture. macOS asks for the **Screen & System Audio Recording** permission the first time; grant it, then quit and relaunch TracePixels. See the [README](https://github.com/flight-tom/TracePixels#first-run) for the full walkthrough.

Requires macOS 14 (Sonoma) or later. The app is a Universal binary (Apple silicon and Intel).

Every release asset has a matching `.sha256` file; check it with `shasum -a 256 -c TracePixels-<version>.dmg.sha256`.

Because the ad-hoc signature changes with each release, macOS may ask you to grant the Screen Recording permission again after you update.
