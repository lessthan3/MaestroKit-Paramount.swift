# Paramount Integration Guide — MaestroKit (Swift / iOS & tvOS)

This guide walks the Paramount client app through integrating **MaestroKit** end-to-end: install, configure, wire the event delegate, present the panel, push player state, feed Key Moments, apply remote config, render overlays, and handle the edge cases the SDK can throw at the host.

---

## Table of Contents

1. [Requirements](#1-requirements)
2. [Installation](#2-installation)
3. [Configuration at app launch](#3-configuration-at-app-launch)
4. [Implementing the event delegate](#4-implementing-the-event-delegate)
5. [Starting and stopping an event](#5-starting-and-stopping-an-event)
6. [Pushing player state into the SDK](#6-pushing-player-state-into-the-sdk)
7. [Presenting the Maestro panel](#7-presenting-the-maestro-panel)
8. [Key Moments](#8-key-moments)
9. [Remote config (`maestro_config`)](#9-remote-config-maestro_config)
10. [Rendering overlays](#10-rendering-overlays)
11. [Analytics](#11-analytics)
12. [Reference: public types](#12-reference-public-types)
13. [Edge cases & gotchas](#13-edge-cases--gotchas)
14. [Troubleshooting checklist](#14-troubleshooting-checklist)
15. [Appendix: minimal end-to-end example](#appendix-minimal-end-to-end-example)

---

## 1. Requirements

| Target          | Minimum |
|---|---|
| iOS deployment  | 18.0    |
| tvOS deployment | 18.0    |
| Swift           | 6.2     |
| Xcode           | 16+     |

MaestroKit is shipped as prebuilt XCFrameworks via a Swift Package.

---

## 2. Installation

### Swift Package Manager

Add the package as described in this repo's `README.md`, then add the **`MaestroKit`** product to your app target.

In your app target, import:

```swift
import MaestroKitParamount
```

That single import is all you need — every public type referenced in this guide is available from `MaestroKitParamount`. The package also contains `MaestroSentryLink` and `MaestroRiveLink` targets; they exist only so the SDK's runtime dependencies are linked into your app. Don't import them.

### Fonts

The panel renders in Proxima Nova, which **ships inside the SDK** and is registered automatically the first time `MaestroManager.shared` is accessed. There is nothing to add to your `Info.plist`.

---

## 3. Configuration at app launch

Call `configure` once, as early as possible (typically in your `App`'s `init` or your scene's bootstrap).

```swift
import MaestroKitParamount

@main
struct ParamountApp: App {
    init() {
        Task {
            await MaestroManager.shared.configure(
                siteID: "YOUR_SITE_ID",
                showHelloWorld: false,                 // debug-only; leave false in prod
                maestroWorkingEnvironment: .prod       // .test | .qa | .prod
            )
        }
    }
    // …
}
```

### Notes

- `MaestroManager.shared` is an **actor**. Every method is `async`.
- `configure` is idempotent — calling it again overwrites the cached site ID, environment, and `showHelloWorld` flag. The new values apply to the **next** event you start.
- `showHelloWorld: true` enables a built-in placeholder overlay used during onboarding/QA. Keep it off in production.
- `maestroWorkingEnvironment` selects which stats backend the panel reads from: `.prod` uses production, `.test` and `.qa` use the non-production backend. To point at a different backend, pass `urls:` (see §13.9).

### Live chat token provider

Pass a `ChatTokenProvider` to `configure` so the SDK can post to live chat as the signed-in viewer. Live chat is available on iOS and iPadOS only.

```swift
struct AppChatTokenProvider: ChatTokenProvider {
    func getChatToken() async -> String? {
        await Session.current.chatToken()   // your app's token source; nil when signed out
    }
}

await MaestroManager.shared.configure(
    siteID: "YOUR_SITE_ID",
    chatTokenProvider: AppChatTokenProvider()
)
```

- The SDK calls the provider when a chat action needs a token (joining, sending, or retrying a message) and again after the server rejects a token (401). It never calls on a timer, and it reuses the token it already holds in between.
- Set the chat header and guidelines link with `chatConfiguration: ChatConfiguration(title:guidelinesURL:)` on the same `configure` call. Both default to empty.
- Returning `nil` (signed out) keeps chat read-only: the viewer can't join or send.
- Don't log the token or include it in crash reports. The SDK doesn't log it.
- Each `configure` call replaces the chat provider and configuration. Omitting `chatTokenProvider` leaves chat read-only. The `configure(siteID:showHelloWorld:maestroWorkingEnvironment:)` overload keeps the current provider and configuration.

### Live chat panel

Create one `ParamountChatController` per Chat tab, point it at the event, and show `ParamountChatPanel` with it:

```swift
@State private var chat = ParamountChatController()

Group {
    if let presenter = chat.presenter {
        ParamountChatPanel(presenter: presenter)
    }
}
.task(id: eventID) {
    await chat.setChatContext(eventId: eventID, chatEnabled: true)
}
```

- `setChatContext(eventId:chatEnabled:)` switches the chat to another event without recreating the SDK. Pass `chatEnabled: false` to hide chat for an event.
- `onEvent` receives `ParamountChatEvent`: `.joined(username:)`, `.error(message:)`, and `.guidelinesTapped(url:)`.
- `setPlaybackPosition(_:)` takes `.live` or `.latent`. The spoiler gate isn't built yet, so the value is stored only.
- The panel collects chat while it is on screen and the app is active.

Note: the controller currently exposes the presenter, and the panel takes it directly. Use `presenter` as shown until the panel takes the controller.

---

## 4. Implementing the event delegate

The delegate is the SDK's only way to talk back to your app. Implement `MaestroEventDelegate` (the Paramount extension), which adds the Key Moments callbacks on top of the base lifecycle methods.

```swift
import MaestroKitParamount
import SwiftUI

@MainActor
final class ParamountMaestroDelegate: MaestroEventDelegate {
    typealias MaestroOverlayEvent = MaestroKitParamount.MaestroOverlayEvent

    weak var host: ParamountPlayerHost?   // your player coordinator / view model

    // MARK: - Base lifecycle

    // Required by the base protocol but not used by Paramount — Key Moments are
    // content-id based (see `onKeyMomentSelected`). Leave these empty.
    func userRequestedNewKeyPlaysData() { }
    func playClip(atIndex index: Int) { }

    func shouldShowPanel() {
        host?.presentMaestroPanel()
    }

    func shouldHidePanel() {
        host?.dismissMaestroPanel()
    }

    func shouldShowOverlay(event: MaestroOverlayEvent) async {
        host?.currentOverlay = event
    }

    func shouldHideOverlay() async {
        host?.currentOverlay = nil
    }

    func trackAction(analytics: [String: String]) {
        host?.analytics.track(action: analytics)
    }

    func trackImpression(analytics: [String: String]) {
        host?.analytics.trackImpression(analytics)
    }

    func playPauseButtonPressed() {
        host?.togglePlayback()
    }

    // MARK: - Paramount callbacks

    func onKeyMomentSelected(contentId: String) {
        // The user tapped a Key Moment. Play that clip. See §8.
        host?.playKeyMoment(contentId: contentId)
    }

    func onKeyMomentsSortOrderChanged(sortOrder: MaestroParamountKeyMomentsSortOrder) {
        // Optional: persist the user's choice. See §8.
        host?.preferredKeyMomentsSort = sortOrder
    }

    func onKeyMomentsRefreshNeeded() {
        // The SDK needs fresh Key Moments. Fetch and push them. See §8.
        host?.reloadKeyMoments()
    }
}
```

All delegate callbacks are delivered on the main actor.

### Critical lifecycle rule

`MaestroManager` **holds the delegate weakly.** You must retain it yourself (typically on your view model or app coordinator). If the delegate deallocates, all callbacks silently stop.

---

## 5. Starting and stopping an event

```swift
// 1. Start watching, handing over the delegate.
let interface: any MaestroEventInterface =
    await MaestroManager.shared.userDidStartWatchingEvents(
        eventIDs: ["EVENT_ID"],
        delegate: myDelegate
    )

// 2. Hold onto `interface` — you'll call back into it from your player.
host.maestroInterface = interface

// 3. End the event when the player closes.
await MaestroManager.shared.userDidStopWatchingEvents(["EVENT_ID"])
host.maestroInterface = nil
```

Use the `delegate:` overload shown above — it returns the Paramount `MaestroEventInterface` directly, with the Key Moments and second-screen methods available. The overload without `delegate:` returns the base interface type and uses whatever delegate was last assigned.

Deprecated singular forms (`userDidStartWatchingEvent(eventID:delegate:)`, `userDidStopWatchingEvent(_:)`) still work but emit warnings — prefer the plural variants.

### Re-starting an event

Calling `userDidStartWatchingEvents` while another event is active is **safe**: the SDK releases the previous event and creates a fresh one. You do **not** need to call `userDidStopWatchingEvents` first. See §13.3.

---

## 6. Pushing player state into the SDK

`MaestroEventInterface` is your one-way pipe from the host player → SDK. All calls are `@MainActor`.

```swift
// Timecode — called continuously by your player (every 250–1000ms is typical).
// The value is UTC epoch **seconds** (wall-clock), not player playback offset.
interface.updatePlayerTimeCode(timeCode: Date().timeIntervalSince1970)

// Notify the SDK when your player handles its panel events:
interface.didShowPanel(panelTypeId: nil)   // confirm `shouldShowPanel()`
interface.didHidePanel()                   // confirm `shouldHidePanel()`

// Host-initiated overlay dismissal (e.g. your player hides the overlay layer):
interface.didHideOverlay()

// Replace the event-id set (e.g. the user switched streams):
interface.updateEventData(eventIDs: ["NEW_EVENT_ID"])

// Second-screen state — see §11:
interface.setSecondScreenState(state: ParamountSecondScreenState(enabled: true, playerSessionId: sessionId))
interface.setSecondScreenState(state: nil)  // disabled
```

Send **timecode in UTC epoch seconds as a `TimeInterval`** (e.g. `Date().timeIntervalSince1970`). See §13.6.

`didShowPanel(panelTypeId:)` takes an optional tab. Pass `nil` — the panel reports which tab is visible on its own.

---

## 7. Presenting the Maestro panel

`MaestroPanel` is a SwiftUI view. Drop it into whichever side-rail / sheet container your player uses.

```swift
import MaestroKitParamount

struct PlayerScreen: View {
    @Bindable var host: ParamountPlayerHost

    var body: some View {
        HStack(spacing: 0) {
            VideoPlayerLayer()
            if host.isPanelVisible {
                MaestroPanel(width: 453)             // pass nil for flex width
                    .transition(.move(edge: .trailing))
                    .onAppear { host.maestroInterface?.didShowPanel(panelTypeId: nil) }
                    .onDisappear { host.maestroInterface?.didHidePanel() }
            }
        }
    }
}
```

### `MaestroPanel` parameters

| Parameter | Default | Purpose |
|---|---|---|
| `width` | `nil` | Maximum width in points. `nil` lets the panel fill its container. |
| `singlePanel` | `nil` | Show one tab only, with no tab bar: `.paramountStats` or `.paramountKeyMoments`. `nil` shows every tab. |
| `maestroManager` | `.shared` | Override only for advanced testing. |

The panel has two tabs:

| `MaestroPanelType` | Title | Content |
|---|---|---|
| `.paramountStats` | Stats | Live and pregame stats for the event (UFC and NFL layouts). |
| `.paramountKeyMoments` | Key Moments | The Key Moments list your app supplies (§8). |

### Panel show/hide contract

| Step | Who acts | Method |
|---|---|---|
| 1 | SDK requests | `shouldShowPanel()` on your delegate |
| 2 | App presents `MaestroPanel` | (your UI) |
| 3 | App confirms | `interface.didShowPanel(panelTypeId: nil)` |
| 4 | SDK requests | `shouldHidePanel()` on your delegate |
| 5 | App dismisses | (your UI) |
| 6 | App confirms | `interface.didHidePanel()` |

Skipping the confirmation steps causes the SDK's internal "panel is visible" state to drift; panel analytics depend on it.

Step 1 isn't only a tab-bar interaction: tapping an overlay that targets a panel enters this contract at step 1 too, so your `shouldShowPanel()` must be able to present the panel from anywhere in the session. The SDK selects the target tab before calling you.

### Rotation

The panel keeps the selected tab and its scroll/selection state across rotation, even if your layout tears down and recreates `MaestroPanel`. It also reports the device orientation for analytics on its own — nothing for the host to send.

### tvOS focus

`MaestroPanel` already wraps itself in a focus section. Make sure your host view doesn't trap focus on a sibling — wrap the rest of your screen in its own focus section.

---

## 8. Key Moments

The Key Moments tab lists clips **your app supplies**. Playback is yours too: the SDK tells you which clip the user picked, and you report progress back so the list can show it.

### Flow

1. The SDK calls `onKeyMomentsRefreshNeeded()` when it needs data.
2. Your app fetches the moments and pushes them:

   ```swift
   let moments: [ParamountKeyMoment] = try await keyMomentsService.fetch(eventID)
   interface.updateKeyPlaysData(to: moments)
   ```

   Push again whenever your list changes. Each call **replaces** the list.
3. The user taps a moment → `onKeyMomentSelected(contentId:)`. Play that clip.
4. While it plays, report progress from `0.0` to `1.0`:

   ```swift
   interface.updateKeyMomentsProgress(contentId: contentId, progress: 0.42)
   // …
   interface.updateKeyMomentsProgress(contentId: contentId, progress: 1.0)   // finished
   ```

### `ParamountKeyMoment`

| Field | Type | Notes |
|---|---|---|
| `contentId` | `String` | Your clip identifier. Echoed back in `onKeyMomentSelected(contentId:)` and expected by `updateKeyMomentsProgress`. |
| `actionTime` | `String` | Display time of the moment (e.g. the game clock). |
| `airDate` | `Int64` | Air date, epoch milliseconds. |
| `duration` | `Int32` | Clip length in seconds. |
| `label` | `String` | Short label. |
| `title` | `String` | Clip title. |
| `mediaType` | `String` | Media type from your catalog. |
| `thumbnailSets` | `[ParamountThumbnail]` | Thumbnails; the first is shown. |

### Sort order

Users can sort the list **Oldest First** (the default) or **Newest First**. When they change it, the SDK calls `onKeyMomentsSortOrderChanged(sortOrder:)`. You can also read or set it:

```swift
let current = interface.keyMomentSortOrder                 // nil until the tab has loaded
interface.setKeyMomentsSortOrder(sortOrder: .newestFirst)
```

Sort order is per event — it resets to the default when a new event starts. Re-apply a saved preference after `userDidStartWatchingEvents` if you persist it. The default can also come from remote config (§9, `highlightsDefaultSort`).

---

## 9. Remote config (`maestro_config`)

Pass your `maestro_config` payload for the user's A/B variant to the SDK as-is. It controls stats section order and visibility, data refresh intervals, the idle timer, and the default Key Moments sort.

```swift
switch await MaestroManager.shared.setRemoteConfig(json: maestroConfigJSON) {
case .success:
    break
case .failure(let error):
    log.error("maestro_config rejected: \(error.description)")
}
```

- **Call it whenever you have the config** — before or during an event. The SDK keeps it and applies it to every event the user watches until you call `setRemoteConfig` again. No need to re-push when the event changes.
- **Each call replaces the whole config.** Always pass the complete `maestro_config`; it isn't merged with the previous one.
- Pass the **original JSON text**. Don't decode and re-encode it — keys your app doesn't model would be lost, including ones a newer SDK understands.
- If the payload isn't a JSON object, you get `.failure(.invalidOverrideValue("maestro_config"))` and the previous config stays in place.

### Config JSON shape

```json
{
  "sports": {
    "ufc": {
      "stats": {
        "refreshInterval": 10.0,
        "snapshotDebounceInterval": 10.0,
        "idleTimer": 60.0,
        "sections": {
          "h2h": {
            "pre":  ["tale-of-the-tape", "event-details"],
            "live": ["fight-overview", "damage-taken", "position-striking", "event-details"],
            "post": ["fight-overview", "damage-taken", "judges-scores", "event-details"]
          }
        }
      },
      "highlights": { "defaultSort": "airDate_DESC" }
    }
  }
}
```

- **Intervals and the idle timer** are in seconds and may be decimals (`10.0`). Leave a key out, or set it to zero or less, to keep the SDK default.
- **`refreshInterval`** (or `dataRefreshInterval`) sets how often stats refresh. A new value applies from the next refresh. **`snapshotDebounceInterval`** throttles fight-snapshot updates.
- **`idleTimer`**: after this many seconds without interaction, the fight carousel returns to the live fight. Default 10 seconds.
- **`defaultSort`**: a value ending in `DESC` (`airDate_DESC`, `DESC`) sorts Key Moments newest first; anything else sorts oldest first. It sets the initial order only — the user's own choice still wins.
- **Phases** `pre`, `live`, `post` follow the status of the **selected fight**.
- **Card names**: `fight-overview`, `damage-taken`, `position-striking`, `judges-scores`, `tale-of-the-tape`, `event-details`. Underscored spellings (`tale_of_the_tape`) work too.
- **Order is render order.** A card left out of the array is hidden, and a listed card only shows when its data exists. Duplicates are ignored. An empty or unrecognized array keeps the built-in order for that phase.
- A payload nested under a `config` key (e.g. a whole variants entry) is read the same as a bare one.
- Everything else is ignored, including the `enabled` flags on `stats` and `highlights` — panel availability comes from the panel configuration, not from `maestro_config`.

### Reading back what's in force

The payload can carry settings for several sports. The SDK applies the block that matches the event on screen. To see what's actually in force:

```swift
if let config = await MaestroManager.shared.appliedRemoteConfig() {
    print(config.idleTimerSeconds, config.dataRefreshIntervalSeconds, config.highlightsDefaultSort)
}
```

Returns `nil` until an event is running.

| `ParamountRemoteConfig` field | Meaning |
|---|---|
| `dataRefreshIntervalSeconds` | How often stats data refreshes. |
| `snapshotDebounceIntervalSeconds` | Debounce for stats snapshot updates. |
| `idleTimerSeconds` | Seconds without interaction before the fight carousel returns to the live fight. |
| `highlightsDefaultSort` | Default Key Moments sort order. |
| `statsCardConfig` | Stats section order and visibility. |

---

## 10. Rendering overlays

When the SDK wants an overlay surfaced, it calls `shouldShowOverlay(event:)` on your delegate with a `MaestroOverlayEvent`. Hand the event to the bundled `MaestroOverlay` SwiftUI view, layered over your video:

```swift
import MaestroKitParamount

struct OverlayLayer: View {
    let event: MaestroOverlayEvent?

    var body: some View {
        if let event {
            MaestroOverlay(
                event: event,
                onOverlayClicked: { /* optional: your own handling */ },
                onOverlayFinished: { /* optional: clear local state */ }
            )
            .id(event.id)
        }
    }
}
```

**Give `MaestroOverlay` the full video area.** It positions itself within the space you give it (corner, edge, or center, as configured for each overlay) and caps its own size on iPhone and iPad. Don't wrap it in a small frame or pin it to a corner yourself.

### Lifecycle

- The overlay plays its animation and dismisses itself when the animation ends. If the animation never signals the end, it dismisses after a fallback timeout: `dismissTimeoutSeconds` if you pass one, otherwise the overlay's configured duration, otherwise 8 seconds.
- When it's gone, the SDK calls `shouldHideOverlay()` on your delegate. Clear your state there.
- A tap (or Siri Remote select) runs the overlay's action. If the overlay targets a panel, the SDK selects that tab and calls `shouldShowPanel()` (§7). Then the overlay dismisses.
- On tvOS, Menu dismisses the overlay.
- To dismiss it yourself, call `interface.didHideOverlay()`. `didShowOverlay()` isn't needed — the overlay reports itself shown.

### Public surface of `MaestroOverlayEvent`

| Property | Type | Notes |
|---|---|---|
| `id` | `String` | Stable identifier. Use it for `Identifiable` / `.id(_:)` view recreation. |

The event is **opaque** beyond `id`. Pass it to `MaestroOverlay` and let the SDK render it.

### `MaestroOverlay` parameters

| Parameter | Default | Purpose |
|---|---|---|
| `event` | — | The event from `shouldShowOverlay(event:)`. |
| `dismissTimeoutSeconds` | `nil` | Fallback auto-dismiss. `nil` uses the overlay's configured duration, else 8 s. |
| `onOverlayClicked` | `nil` | Called when the user activates the overlay. |
| `onOverlayFinished` | `nil` | Called after the overlay finishes (animation end, timeout, tap, or Menu). |
| `maestroManager` | `.shared` | Override only for advanced testing. |

---

## 11. Analytics

The SDK doesn't send analytics itself. Every action and impression comes through the delegate:

```swift
func trackAction(analytics: [String: String])      // fired on user actions
func trackImpression(analytics: [String: String])  // fired when surfaces appear
```

The dictionary keys are stable. Forward them verbatim to your analytics SDK — don't transform them.

The SDK stamps two kinds of context on every event for you:

- **Screen orientation** (`screenOrientation`) — reported by the panel automatically.
- **Second screen** (`secondScreenEnabled`, `playerSessionId`) — from the last `setSecondScreenState(state:)` call. Pass `ParamountSecondScreenState(enabled: true, playerSessionId: …)` when a second screen is active and `nil` when it isn't.

---

## 12. Reference: public types

| Type | Used for |
|---|---|
| `MaestroManager` | The actor singleton you talk to. Access via `MaestroManager.shared`. |
| `MaestroPanel` | SwiftUI view rendering the Maestro panel. |
| `MaestroOverlay` | SwiftUI view that renders a `MaestroOverlayEvent`. |
| `MaestroPanelType` | `.paramountStats` / `.paramountKeyMoments`. |
| `MaestroOverlayEvent` | Overlay payload passed to `shouldShowOverlay`. Public surface: `id`. |
| `MaestroEventDelegate` | Protocol your app implements (Paramount extension — adds `onKeyMomentSelected`, `onKeyMomentsSortOrderChanged`, `onKeyMomentsRefreshNeeded`). |
| `MaestroEventInterface` | Protocol the SDK returns from `userDidStartWatchingEvents`. Your one-way push channel. |
| `ParamountKeyMoment` | One Key Moment, pushed with `updateKeyPlaysData(to:)`. |
| `MaestroParamountKeyMomentsSortOrder` | `.oldestFirst` / `.newestFirst`. |
| `ParamountSecondScreenState` | Second-screen state for analytics: `enabled`, `playerSessionId`. |
| `ParamountRemoteConfig` | The remote config in force, from `appliedRemoteConfig()`. |
| `ParamountUrls` | Optional backend override for `configure(…, urls:)`. |
| `ChatTokenProvider` | Protocol your app implements to supply the viewer's chat token (§3). |
| `ParamountChatPanel` | SwiftUI chat panel for a Chat tab (iOS only). |
| `ParamountChatController` | Switches the chat between events and reports `ParamountChatEvent`s. |
| `ParamountChatEvent` / `ParamountChatPlayback` | Events the chat reports, and the live or latent position it's given. |
| `MaestroPanelOverride` / `MaestroPanelOverrideError` | Used by `setDataToPanel` (§13.10) and returned by `setRemoteConfig`. |
| `MaestroWorkingEnvironment` | `.test` / `.qa` / `.prod`. |

---

## 13. Edge cases & gotchas

### 13.1 The delegate is held weakly

`MaestroManager` keeps the delegate as a `weak` reference. If you write:

```swift
await MaestroManager.shared.userDidStartWatchingEvents(
    eventIDs: [id],
    delegate: ParamountMaestroDelegate()   // ❌ deallocates immediately
)
```

…you'll get zero callbacks. Always retain the delegate on a long-lived object (App, AppDelegate, view model).

### 13.2 `MaestroManager` is an actor

Anything that touches manager state goes through `await`. The `MaestroEventInterface` you get back is `@MainActor` and its methods are synchronous.

### 13.3 Re-starting an event without stopping the previous one

Supported. The SDK releases the previous event and creates a new one. However:

- The `MaestroEventInterface` you held for the old event becomes a no-op. Replace it with the new one.
- Any overlay still showing is finished first — your `shouldHideOverlay()` fires one last time.
- Key Moments data and sort order belong to the old event. Push Key Moments again when the SDK asks (§8).
- Remote config **carries over** — you don't need to re-apply it.

### 13.4 Calling SDK methods before `configure`

If `configure` hasn't been awaited, `userDidStartWatchingEvents` returns a no-op interface and every call on it is dropped. **Always `await configure` before starting an event.**

### 13.5 Empty event IDs

`userDidStartWatchingEvents(eventIDs: [])` returns a no-op interface. Guard upstream.

### 13.6 Timecode units

`updatePlayerTimeCode(timeCode:)` expects **UTC epoch seconds** as a `TimeInterval` (`Date().timeIntervalSince1970`). Don't multiply by 1000 — the SDK converts internally. Passing milliseconds makes time-gated overlays never fire.

### 13.7 Detached interface after stop

After `userDidStopWatchingEvents`, the `MaestroEventInterface` you held is a no-op. Calls don't throw — they're silently dropped. Get a new one by calling `userDidStartWatchingEvents` again.

### 13.8 Hello-World debug mode

`configure(showHelloWorld: true)` always shows a placeholder overlay. Useful as a "is the overlay layer wired?" smoke test; never ship this on.

### 13.9 Working environment and backend URLs

`maestroWorkingEnvironment` picks the stats backend for you. If you need a different one, pass it explicitly:

```swift
await MaestroManager.shared.configure(
    siteID: "YOUR_SITE_ID",
    maestroWorkingEnvironment: .qa,
    urls: ParamountUrls(helios: "<YOUR_STATS_BASE_URL>")
)
```

`urls:` overrides the environment's default. Leave it `nil` unless the Maestro team asks you to set it.

### 13.10 `setDataToPanel` is reserved

`setDataToPanel(_:)` / `setDataToPanels(_:)` accept the panel identifiers `paramountStats` and `paramountKeyMoments` but don't change panel behavior yet. You don't need to call them. Use `setRemoteConfig` (§9) for configuration.

### 13.11 Overlay ID equality

Overlays are deduplicated by `event.id`. Two overlay events with the **same** id won't re-fire `shouldShowOverlay`.

### 13.12 Order of operations per event

The correct sequence after `await configure`:

1. `setRemoteConfig(json:)` — any time; it's retained.
2. `await userDidStartWatchingEvents(eventIDs:delegate:)` — capture the returned interface.
3. Start pushing timecode with `updatePlayerTimeCode`.
4. Mount `MaestroPanel` and your overlay layer.
5. Answer `onKeyMomentsRefreshNeeded()` with `updateKeyPlaysData(to:)`.

---

## 14. Troubleshooting checklist

| Symptom | Likely cause | Fix |
|---|---|---|
| No callbacks at all | Delegate deallocated (held weakly) | Retain on a long-lived owner. |
| Every interface call does nothing | `configure` not awaited, empty `eventIDs`, or the event was stopped | See §13.4, §13.5, §13.7. |
| Key Moments tab stuck loading or empty | App never answered `onKeyMomentsRefreshNeeded()` | Push data with `updateKeyPlaysData(to:)` (§8). |
| Key Moment progress doesn't move | `contentId` mismatch | Report progress with the exact `contentId` from `onKeyMomentSelected`. |
| Overlay never appears | App didn't render `MaestroOverlay` from `shouldShowOverlay`, or timecode is in milliseconds | Mount `MaestroOverlay(event:)`; send timecode in seconds (§13.6). |
| Overlay appears in the wrong place or tiny | Overlay wrapped in a small frame | Give `MaestroOverlay` the full video area (§10). |
| Overlay tap doesn't open the panel | `shouldShowPanel()` can't present from the current screen | Make `shouldShowPanel()` work from anywhere in the session (§7). |
| Stats layout ignores `maestro_config` | Payload not a JSON object, or the block for this sport is missing | Check the `setRemoteConfig` result; inspect `appliedRemoteConfig()` (§9). |
| `trackAction` events missing second-screen fields | `setSecondScreenState` never called | Call it whenever second-screen state changes (§11). |

---

## Appendix: minimal end-to-end example

```swift
import SwiftUI
import MaestroKitParamount

@main
struct ParamountApp: App {
    @State private var host = ParamountPlayerHost()

    init() {
        Task {
            await MaestroManager.shared.configure(
                siteID: "YOUR_SITE_ID",
                maestroWorkingEnvironment: .prod
            )
        }
    }

    var body: some Scene {
        WindowGroup { PlayerScreen(host: host) }
    }
}

@MainActor
@Observable
final class ParamountPlayerHost {
    var maestroInterface: (any MaestroEventInterface)?
    var isPanelVisible = false
    var currentOverlay: MaestroOverlayEvent?
    let delegate = ParamountMaestroDelegate()

    func startEvent(_ id: String, maestroConfigJSON: String) async {
        delegate.host = self
        await MaestroManager.shared.setRemoteConfig(json: maestroConfigJSON)
        maestroInterface = await MaestroManager.shared.userDidStartWatchingEvents(
            eventIDs: [id],
            delegate: delegate
        )
    }

    func stopEvent(_ id: String) async {
        await MaestroManager.shared.userDidStopWatchingEvents([id])
        maestroInterface = nil
    }

    func reloadKeyMoments() {
        Task {
            let moments: [ParamountKeyMoment] = await fetchKeyMoments()   // your service
            maestroInterface?.updateKeyPlaysData(to: moments)
        }
    }

    // presentMaestroPanel(), dismissMaestroPanel(), playKeyMoment(contentId:), … — your player.
}

struct PlayerScreen: View {
    let host: ParamountPlayerHost

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                VideoPlayerLayer()
                    .task { await host.startEvent("EVENT_ID", maestroConfigJSON: "{}") }
                if let overlay = host.currentOverlay {
                    MaestroOverlay(event: overlay).id(overlay.id)
                }
            }
            if host.isPanelVisible {
                MaestroPanel(width: 453)
                    .onAppear { host.maestroInterface?.didShowPanel(panelTypeId: nil) }
                    .onDisappear { host.maestroInterface?.didHidePanel() }
            }
        }
    }
}
```

---

**Owner:** Maestro iOS team
**Questions:** contact your Maestro representative or file an issue on the SDK repo.
