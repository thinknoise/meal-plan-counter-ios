# Meal Plan Counter for iPhone

A native SwiftUI version of the meal counter. It works offline and stores the name, counts, and meal activity timestamps in this iPhone's app storage. It does not connect to CalArts or read an official meal balance.

## Run on an iPhone

1. Open `Meal Plan Counter.xcodeproj` in Xcode 16 or later.
2. Select the `Meal Plan Counter` scheme and your iPhone as the run destination. Running on an iPad or Simulator does not install the app on your iPhone.
3. In **Signing & Capabilities**, select your Apple development team if Xcode asks. The bundle identifier is `com.lilyfritsch.mealplancounter`.
4. Press **Run**. On first launch, enter Lily's name and the meal total from her plan.

The counter supports one-tap meal use, one-step undo, and manual corrections under **Account**. The **Record** tab shows the starting balance and each meal use with its timestamp and remaining balance. Undo removes the latest meal use from the record. Manual count corrections appear as plan updates. Plans created before the Record tab retain their balance and start the record with a snapshot. **Clear plan** removes its saved data from the iPhone.

The home screen shows Steve’s Café’s current service period using the phone clock and the café’s Los Angeles time zone. The regular weekly schedule is embedded for offline use and was checked against [Bon Appétit’s CalArts café page](https://calarts.cafebonappetit.com/) on September 26, 2026. Tap **View Hours** for the full schedule or **Today’s Menu** for current hours and food. Special hours, holidays, and academic breaks may differ from the regular schedule.

The original Figma Make web preview is outside this project. It contains a student ID image and student-number field, so it is intentionally excluded from this repository.

For TestFlight and store listing details, see [App Store Connect setup](APP_STORE_CONNECT.md). The app's [privacy policy](PRIVACY.md) is available as a public URL for App Store Connect.
