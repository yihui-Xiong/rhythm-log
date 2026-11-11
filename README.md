# Rhythm Log

A native iPhone app for exploring heart rate, heart rate variability (HRV), training, and daily activity from Apple Health. Day, Week, Month, and Year views connect individual readings to longer-term patterns. Training and daytime recovery work with available daytime records alone. Sleep timing and overnight vitals appear when recorded.

- **Day** — Explore the 24-hour dial, tap through to heart readings and workouts, or open the 30-day HRV history.
- **Training** — Compare eight rolling seven-day blocks, drill into workouts and heart-rate zones, and compare average heart rate at similar paces. The latest block ends yesterday.
- **Recovery** — Explore daytime HRV, resting heart rate, and steps. With sleep data, view sleep timing by wake date, overnight HRV, and four overnight vitals.
- **Month and Year** — Use monthly calendars to open a specific day and yearly charts to see monthly averages.

[Onboarding](https://yihui-xiong.github.io/rhythm-log/) · [App story](https://yihui-xiong.github.io/rhythm-log/portfolio/) · [Evidence and methods](https://yihui-xiong.github.io/rhythm-log/methods.html) · [简体中文说明](README.zh-Hans.md)

## Run the app

Open `HealthTimeline.xcodeproj` with an Xcode version that includes the iOS 27 SDK. The app deployment target is iOS 17. APIs for Apple-provided workout zones require iOS 27. On earlier systems, users can enter their own boundaries in **Settings → Manual Heart Rate Zones**.

**Simulator.** In **Product → Scheme → Edit Scheme → Run → Arguments**, add `-rhythmDemo` or `-rhythmDemoNoSleep` under **Arguments Passed On Launch**. Run on an iPhone simulator. Tap **Connect Apple Health** to enter the sample experience. These flags use synthetic records and are available in Debug builds.

**iPhone.** Under **Signing & Capabilities**, choose your development team and a unique bundle identifier. Keep the HealthKit capability enabled. Run on a supported iPhone and choose the data types to share when Apple Health prompts. To revisit access, open **Settings → Update Apple Health Access** in Rhythm Log. If a chart is empty, check Apple Health for both the underlying records and the app’s read permissions.

## Data and interpretation

Rhythm Log reads authorized HealthKit records on the device. The app’s queries request read access only. Its reference bands and HRV score describe personal history and are intended for exploratory use. The public screenshots contain synthetic records.

The shared workout screen uses time-window heart-rate readings for its displayed average and maximum. The pace scatterplot uses the workout’s HealthKit average when available, so the figures can differ. One-minute recovery appears only when a HealthKit recovery sample can be matched to a workout. See the [methods page](docs/methods.html) for the full definitions and evidence.
