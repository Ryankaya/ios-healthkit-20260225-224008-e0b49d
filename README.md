# ios-healthkit-20260225-224008-e0b49d

A minimal SwiftUI iOS app that demonstrates **HealthKit** by requesting permission to read step count data and querying today's cumulative steps with Swift concurrency.

## Feature Focus
- Requests read authorization for  from HealthKit.
- Uses  to fetch today's cumulative step count.
- Displays authorization status and current result in a compact UI.

## Apple Documentation Used
- https://developer.apple.com/documentation/healthkit
- https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
- https://developer.apple.com/documentation/healthkit/reading-data-from-healthkit

## Run
1. Open  in Xcode.
2. Select an iPhone device (or simulator with Health data support).
3. Run and tap **Request Access + Load Steps**.
