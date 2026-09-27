# App Store Connect setup

## New app record

- Platform: iOS
- Name: Meal Plan Counter
- Primary language: English (U.S.)
- Bundle ID: `com.lilyfritsch.mealplancounter`
- SKU: `meal-plan-counter-ios`
- User access: Full Access

Create this record before uploading the first build. Use the Apple developer team with ID `JULFQWJVD6`, which signs the Xcode project. If the bundle ID does not appear in the App Store Connect picker, register it as an explicit App ID in Certificates, Identifiers & Profiles first.

## Store information draft

- Category: Food & Drink
- Subtitle: Track your campus meals
- Support URL: https://github.com/thinknoise/meal-plan-counter-ios/issues
- Privacy policy URL: https://github.com/thinknoise/meal-plan-counter-ios/blob/main/PRIVACY.md
- Privacy declaration: No data collected by the app. The name and meal counts are stored locally on the iPhone. Opening the external café website is optional.
- TestFlight “What to Test”: Set up a meal total, use a meal, undo it, edit the plan, and check that the café service shown matches the current Los Angeles time. Café hours are the regular schedule and can change on holidays or breaks.

This is a draft for the app owner to review before a public App Store release. TestFlight distribution does not publish the app on the App Store.
