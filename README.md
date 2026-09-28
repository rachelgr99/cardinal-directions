# Cardinal Directions

Native iOS app for getting around Stanford on the free Marguerite shuttles — live buses, live ETAs, and multi-stop trip planning, in Stanford cardinal with a Gen Z coat of paint.

## What it does

- **Live map home screen** — your location, the Marguerite lines running around you drawn as route overlays, and every nearby bus as a pin with its line badge and minutes-away chip.
- **Nearby deck** — a Waze-style bottom deck with the closest buses and the stops you can walk to, with live vs. scheduled ETAs called out.
- **Trip planner** — pick a start, a destination, and as many stops in between as you want; the app searches the shuttle network and returns a few ranked options with walk → ride → transfer → walk steps, and draws the chosen one on the map.

## Data

Live data comes straight from the ETA Spot feed behind [Stanford's Marguerite live map](https://transportation.stanford.edu/getting-stanford/marguerite/marguerite-live-map) (`https://supublic.etaspot.net/service.php`): route patterns and shapes, all stops, live vehicle positions, and per-stop arrival predictions. Vehicles and ETAs refresh every 12 seconds.

Routing is a Dijkstra search over a graph built from each line's ordered stops plus short walking transfers between nearby stops. Waiting time uses the real predicted ETA at the boarding stop when the feed has one, and a headway estimate otherwise.

## Build

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The `.xcodeproj` is generated, not committed.

```sh
xcodegen generate
open CardinalDirections.xcodeproj
```

Or from the command line:

```sh
xcodebuild -project CardinalDirections.xcodeproj -scheme CardinalDirections \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Layout

```
CardinalDirections/Sources/
  Models/      ETA Spot payloads: Stop, Line, Vehicle, Arrival
  Services/    API client, polyline decoding, transit graph, trip planner, location, place search
  State/       TransitStore — loading, polling, nearby queries, planning
  Design/      Stanford palette, rounded type scale, chips/badges/buttons, copy
  Views/       HomeView map, NearbyDeck, TripPlannerSheet, PlaceSearchSheet, PlanDetailCard
CardinalDirections/Tests/
Tools/MakeAppIcon.swift   regenerates the app icon PNG
```
