# Horological Heartbeat

Horological Heartbeat is a macOS menu bar application that brings the precision and beauty of horology (the study and measurement of time) to your desktop. Inspired by the heartbeat of mechanical watches, this app visualizes the passage of time in a unique, rhythmic, and visually engaging way, blending the art of traditional watchmaking with the power of modern computing.

---

## ✨ Why Horological Heartbeat is Cool
- **Mechanical Watch Aesthetics**: Emulates the pulse and rhythm of a mechanical watch, offering a meditative and visually pleasing experience.
- **Menu Bar Integration**: Sits unobtrusively in your menu bar, always accessible without cluttering your workspace.
- **Precision Timekeeping**: Uses NTP (Network Time Protocol) to synchronize with atomic clocks, ensuring your time is as accurate as possible.
- **Stats & Insights**: Provides statistics about time drift, synchronization events, and your system's time accuracy.
- **Minimalist Design**: Focuses on clarity and elegance, making it both functional and beautiful.

---

## 🕰️ What the App Does
- **Displays a Pulsing Heartbeat**: The menu bar icon pulses in real time, mimicking the ticking of a watch.
- **Shows Current Time**: Hover or click to see the precise current time.
- **Synchronizes with NTP Servers**: Periodically checks and corrects your system clock using trusted NTP servers.
- **Drift Monitoring**: Tracks how much your system clock drifts over time and displays this information in the Stats view.
- **Stats View**: Offers a breakdown of synchronization events, drift history, and other timing metrics.

---

## 🚫 What the App Does NOT Do
- **Does Not Change System Time**: The app monitors and reports drift but does not modify your system clock (due to macOS security restrictions).
- **No Alarm or Timer Features**: This is not a timer, stopwatch, or alarm app.
- **No Cloud Sync**: All data is local; nothing is sent to the cloud or external services (except for NTP queries).
- **No Notifications**: The app is intentionally non-intrusive and does not send notifications.

---

## 📖 How to Read the App
- **Menu Bar Icon**: The pulsing icon represents the heartbeat of time. Each pulse corresponds to a second, just like a watch tick.
- **Stats View**: Accessed by clicking the menu bar icon and selecting "Stats." Here you can see:
  - **Current Drift**: How far your system clock is from the NTP reference.
  - **Synchronization Events**: When and how often the app checked the time.
  - **Pulse Graph**: Visualizes the heartbeat and any detected drift.
- **Pulse View**: A graphical representation of the heartbeat, showing the rhythm and any irregularities.

---

## 🚀 How to Use Horological Heartbeat
1. **Install the App**: Build and run from Xcode, or download the pre-built binary (if available).
2. **Launch the App**: The icon will appear in your menu bar.
3. **View the Heartbeat**: Watch the icon pulse in real time.
4. **Access Stats**: Click the icon and select "Stats" to view drift and synchronization details.
5. **Settings**: (If available) Adjust NTP server preferences or pulse animation speed.
6. **Quit**: Use the menu bar icon to quit the app when done.

---

## 🛠️ Building from Source
1. **Clone the Repository**:
   ```sh
   git clone https://github.com/yourusername/HorologicalHeartbeat.git
   ```
2. **Open in Xcode**:
   - Open `HorologicalHeartbeat.xcodeproj`.
3. **Build & Run**:
   - Select the target and run the app. The menu bar icon should appear.

---

## 🧩 Project Structure
- `HorologicalHeartbeat/` — Main source code
  - `ContentView.swift` — Main UI
  - `MenuBarController.swift` — Handles menu bar integration
  - `NTPClient.swift` — NTP synchronization logic
  - `DriftStore.swift` — Drift tracking and storage
  - `PulseView.swift` — Heartbeat visualization
  - `StatsView.swift` — Statistics and drift display
  - `TimeEngine.swift` — Core timekeeping logic
  - `HorologicalHeartbeatApp.swift` — App entry point
  - `Info.plist`, `.entitlements` — App configuration
- `HorologicalHeartbeat.xcodeproj/` — Xcode project files

---

## 🔒 Privacy & Security
- **No Personal Data Collected**: The app does not collect, store, or transmit any personal data.
- **Network Usage**: Only connects to NTP servers for time synchronization.
- **Open Source**: Review the code to verify privacy claims.

---

## 💡 Inspiration
Horological Heartbeat is inspired by the timeless beauty of mechanical watches and the challenge of precise timekeeping in the digital age. It’s a tribute to horologists and anyone who appreciates the art and science of time.

---

## 🙋 FAQ
- **Q: Why doesn’t the app set my system clock?**
  - A: macOS restricts apps from changing system time for security reasons. The app reports drift but cannot correct it.
- **Q: Is my data safe?**
  - A: Yes. The app only communicates with NTP servers and does not store or transmit personal data.
- **Q: Can I use my own NTP server?**
  - A: If the feature is available in settings, you can specify a custom NTP server.

---

## 📬 Feedback & Contributions
Pull requests, issues, and suggestions are welcome! Please open an issue or submit a PR on GitHub.

---

## 📜 License
This project is licensed under the MIT License. See the LICENSE file for details.
