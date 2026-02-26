# ios-healthkit-20260225-224008-e0b49d

A SwiftUI iOS app that demonstrates **HealthKit** with a stronger permission UX and a chart-driven activity view.

## What's Improved
- Clear authorization states: not requested, requesting, authorized, denied, unavailable, and error.
- Dedicated **Request Access** and **Refresh Data** actions.
- Card-based interface with progress and status emphasis.
- **7-day step chart** (Swift Charts) plus weekly average.
- Today's steps + completion progress against a 10,000-step goal.

## Feature Focus
- Requests read authorization for `stepCount` from HealthKit.
- Reads today's cumulative steps using `HKStatisticsQuery`.
- Builds a 7-day trend using `HKStatisticsCollectionQuery`.

## Apple Documentation Used
- https://developer.apple.com/documentation/healthkit
- https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
- https://developer.apple.com/documentation/healthkit/reading-data-from-healthkit

## Run
1. Open `ios-healthkit-20260225-224008-e0b49d.xcodeproj` in Xcode.
2. Select an iPhone device (or simulator with Health data support).
3. Tap **Request Access**, allow Health permissions, then tap **Refresh Data**.
