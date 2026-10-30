# Can a live mic meter in the menu bar cost almost nothing?

Researched 2026-10-30. The question: Carbon's status item shows three vertical bars that move with the person's voice while transcribing. On macOS 26 it costs about 18% of a core on Carbon's main thread and about 17% in WindowServer (Debug build, measured with `sample` and `top`). Can it be made nearly free, and how? If not, the feature gets dropped.

What Carbon does today:

- [`MenuBarGlyph`](../../App/Sources/MenuBarMenu.swift) is the label of a SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.menu)`. A `.task` loop wakes every 33 ms, moves the bars toward the level, and rebuilds the meter `NSImage` and the "FR" badge `NSImage`.
- `micLevel` is set on the main actor once per tap buffer, about every 100 ms ([Recorder.swift](../../CarbonCore/Sources/CarbonCore/Recorder.swift), `capture`). The tap asks for `sampleRate / 10` frames ([MicrophoneSource.swift](../../App/Sources/Adapters/MicrophoneSource.swift)).
- [`SoundLevel`](../../CarbonCore/Sources/CarbonCore/SoundLevel.swift) computes RMS in a scalar Swift loop, and does it twice per mic buffer (`isSound`, then `meter`).
- The profile was dominated by SwiftUI graph updates, `-[NSStatusBarButton setImage:]`, `-[NSStatusItem _adjustLength]` and `CA::Transaction::commit`.

Method: Apple documentation, the archived Energy Efficiency Guide, WWDC and tech-talk pages, Apple Developer Forums threads, and the source and issue threads of two open-source macOS 26 menu bar apps that hit this exact problem, read at the pinned commits below. Nothing was built or run. Anything I concluded myself is marked **(inference)**. Anything I could not settle is marked **(unverified)**.

## Verdict

**Yes, the meter can be made almost free, but only if it is no longer a SwiftUI `MenuBarExtra` label.** The cheap design is an AppKit `NSStatusItem` whose button holds a small layer-backed view with three `CALayer` bars. You move the bars by changing layer geometry about 10 times a second, straight from the mic level you already receive. You never call `setImage:`, never change the item's length while recording, never mark the view for display, and run no timer of your own.

The closest prior art, MenuMeter, shows two live stereo bars in the macOS 26 menu bar this way. Its author measured **about 2% of one core at 30 fps**, down from **about 30%** when the meter was redrawn ([commit e3c18bb](https://github.com/bassepeder/MenuMeter/commit/e3c18bb), [README.md#L50](https://github.com/bassepeder/MenuMeter/blob/ea445f2d4fae9eb6f3da8953a0b0f94f5d3ee089/README.md#L50)). Carbon would update at a third of that rate, with three plain bars.

It is only cheap under these conditions:

1. **The menu has to leave `MenuBarExtra`.** SwiftUI gives you no supported access to the `NSStatusItem` behind a `MenuBarExtra`, and the label can only change by producing a new image. That path is the one that costs 18% today. `NSHostingMenu` (macOS 14.4+) lets the existing SwiftUI `MenuBarMenu` stay as is, as the `NSMenu` of a hand-made status item ([docs](https://developer.apple.com/documentation/swiftui/nshostingmenu)).
2. **On secondary displays the meter is not live.** macOS 26 shows the status item on other displays' menu bars through CPU-rendered "replicant" snapshots. A replicant only updates when the view is redrawn ([MenuMeter main.swift#L224-L226](https://github.com/bassepeder/MenuMeter/blob/ea445f2d4fae9eb6f3da8953a0b0f94f5d3ee089/main.swift#L224-L226)). Either the meter freezes there, or you refresh it a few times a second and pay for each refresh.
3. **You lose automatic template tinting.** Only template images get the system's light, dark and selected coloring ([HIG, The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)). The bars have to be recolored by hand when the appearance changes.
4. **WindowServer's share is not documented anywhere.** Measure it before keeping the feature (see [How to check](#how-to-check-before-keeping-it)).

If Carbon keeps `MenuBarExtra` for the status item, **the meter cannot be made nearly free and should be dropped.** The best you get there is fewer `setImage:` calls: 10 Hz instead of 30, a cached badge, fixed width. That might cut the main-thread cost to about a third, still several percent **(inference)**.

## Sources and pins

| Source | Pin | Why it matters |
|---|---|---|
| MenuMeter | [bassepeder/MenuMeter@ea445f2](https://github.com/bassepeder/MenuMeter/tree/ea445f2d4fae9eb6f3da8953a0b0f94f5d3ee089) | Live stereo level meter in the macOS 26 menu bar, built from `CALayer`s on `NSStatusItem.button`. The commit message and README report its CPU cost. |
| BalanceBar | [huanmeng06/BalanceBar@951d81c](https://github.com/huanmeng06/BalanceBar/tree/951d81c9792c3e9f4e8bdb5dff534c03297cca49), issues [#284](https://github.com/huanmeng06/BalanceBar/issues/284) and [#300](https://github.com/huanmeng06/BalanceBar/issues/300), PR [#304](https://github.com/huanmeng06/BalanceBar/pull/304) | Animated status item icon on macOS 26, with `sample` profiles of the replicant cost. Compares per-frame `setImage:` against a Core Animation path. |
| Apple docs | linked inline | `NSHostingMenu`, `NSView.displayLink`, `CAAnimation.preferredFrameRateRange`, `vDSP_rmsqv`, `installTap`, `kAudioUnitProperty_MeteringMode`, `MenuBarExtra` |
| Apple archive | [Energy Efficiency Guide for Mac Apps](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/), [Core Animation Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/CoreAnimationBasics/CoreAnimationBasics.html) | Timers and wakeups, App Nap, cost of changing layer properties versus redrawing |
| Apple forums | [thread 803501](https://developer.apple.com/forums/thread/803501), [thread 839158](https://developer.apple.com/forums/thread/839158) | SwiftUI animations in a status item turned choppy on macOS 26 |

## 1. The cheapest way to animate inside an `NSStatusItem` on macOS 26

### What macOS 26 does with status items

Apple does not document how status items are hosted on macOS 26. Here is what developers' logs and profiles show:

- **Control Center places the item through a FrontBoard scene.** The app creates an `NSStatusItemScene` in its own process, and Control Center hosts it. A Calendr user's log names the scene `[com.apple.controlcenter:…-NSStatusItemView]` ([Calendr#610](https://github.com/pakerwreah/Calendr/issues/610)). A CodexBar heap snapshot shows an `NSStatusItemScene`, an `NSStatusItemSceneSpecification` and an `NSStatusBarWindow` inside the app ([CodexBar#3377](https://github.com/steipete/CodexBar/issues/3377)).
- **Other displays show "replicants": CPU-rendered snapshots of the item.** BalanceBar's profiles show this chain on the app's main thread: `-[NSStatusItem _updateReplicantsUnlessMenuIsTracking:]` → `_redrawReplicantSnapshot:sourceView:` → `CALayer renderInContext`, then a Gaussian-blurred shadow (`NSStatusItemReplicantShadowView drawRect` → `vImageConvolve`) ([#284](https://github.com/huanmeng06/BalanceBar/issues/284), [#300](https://github.com/huanmeng06/BalanceBar/issues/300)). These symbols are private and appear only in profiles. Apple documents none of this **(unverified as design intent)**.
- **A replicant is refreshed when the view is redrawn, not when a layer moves.** MenuMeter's author wrote: "Moving layers is nearly free, whereas redrawing the view makes AppKit CPU-render a copy of the menu bar item for every replica it keeps (other displays, other menu bar states)" ([main.swift#L224-L226](https://github.com/bassepeder/MenuMeter/blob/ea445f2d4fae9eb6f3da8953a0b0f94f5d3ee089/main.swift#L224-L226)). BalanceBar found that each per-frame `imageView.image = frame` kept the replicant loop going: about 297 `_updateReplicants` per second at 30 fps ([#284 comment](https://github.com/huanmeng06/BalanceBar/issues/284)).

### Does a Core Animation animation on the button show up?

On the active display it does. Elsewhere it does not.

- **BalanceBar first tried a `CAKeyframeAnimation` rotation and rejected it.** The icon did not turn, and they concluded that replicants are `renderInContext` snapshots of the model layer, which never sees a render-server animation ([#284](https://github.com/huanmeng06/BalanceBar/issues/284)).
- **They later shipped that same path as the default "Performance" mode.** It is a BalanceBar-owned `CALayer` in a subview of `statusItem.button`, running a `CAKeyframeAnimation` with `repeatCount = .infinity` ([MenuBarViews.swift#L34-L56, #L185-L203](https://github.com/huanmeng06/BalanceBar/blob/951d81c9792c3e9f4e8bdb5dff534c03297cca49/work/balance-bar/Sources/UI/MenuBar/MenuBarViews.swift#L34-L203)).
  - Its documented limit: "pauses the animation on non-active displays" ([docs/issue-300-animation-performance-plan.md](https://github.com/huanmeng06/BalanceBar/blob/951d81c9792c3e9f4e8bdb5dff534c03297cca49/docs/issue-300-animation-performance-plan.md)).
  - The main thread went from about 74% waiting (bitmap swaps) to about 99.25% waiting ([PR #304](https://github.com/huanmeng06/BalanceBar/pull/304)).
  - **(inference)** The earlier failure was probably seen on a display that showed a replicant. The #284 profiles were taken with an external display.
- **MenuMeter does what Carbon needs.** It changes the bars' layer frames on every tick inside a `CATransaction` with actions disabled, and the meter is live on the menu bar it sits in ([main.swift#L302-L334](https://github.com/bassepeder/MenuMeter/blob/ea445f2d4fae9eb6f3da8953a0b0f94f5d3ee089/main.swift#L302-L334)).
  - For replicas it sets `needsDisplay` at 10 fps when a replica window is on a screen and once a second otherwise. It finds them by looking for other `NSStatusBarWindow`s ([main.swift#L495-L516](https://github.com/bassepeder/MenuMeter/blob/ea445f2d4fae9eb6f3da8953a0b0f94f5d3ee089/main.swift#L495-L516)).

### Is it composited out of process?

- **Changing layer properties is the cheap path.** Apple's Core Animation guide says changing a layer property only changes "the state information associated with the layer object". It describes view drawing as "expensive because it is done using the CPU on the main thread" ([Core Animation Basics](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/CoreAnimationBasics/CoreAnimationBasics.html)).
- **Commits go to a separate render server.** Apple's render-loop talk says the app "submits that to the render server", which runs "in a separate process" ([Tech Talk 10855](https://developer.apple.com/videos/play/tech-talks/10855/)). That talk is about iOS. On macOS the render server is inside WindowServer **(inference)**, which fits Carbon's 17% WindowServer reading.
- **So an in-flight `CAAnimation` costs no per-frame app work, but it is not free.** The render server still composites the menu bar region on every display frame while anything animates.

### Template and vibrancy tinting

- **The system only recolors template images.** The HIG says menu bar icons use black and clear so that "the system can apply other colors to the black areas in each image so it looks good on both dark and light menu bars, and when your menu bar extra is selected" ([HIG, The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)). A `CALayer.backgroundColor` is a resolved `CGColor`, so nothing recolors it.
- **Both apps recolor by hand on appearance change.**
  - MenuMeter resolves its colors inside `effectiveAppearance.performAsCurrentDrawingAppearance` and picks light or dark values from `viewDidChangeEffectiveAppearance` ([main.swift#L287-L311](https://github.com/bassepeder/MenuMeter/blob/ea445f2d4fae9eb6f3da8953a0b0f94f5d3ee089/main.swift#L287-L311)).
  - BalanceBar rasterizes its icon with `contentTintColor` set to `.labelColor`, or to `.selectedMenuItemTextColor` while the button is highlighted ([MenuBarViews.swift#L228-L262](https://github.com/huanmeng06/BalanceBar/blob/951d81c9792c3e9f4e8bdb5dff534c03297cca49/work/balance-bar/Sources/UI/MenuBar/MenuBarViews.swift#L228-L262)).
- **Whether the transparent Tahoe menu bar applies its wallpaper-adaptive vibrancy to a non-template layer is (unverified).** Check it against a light and a dark wallpaper, with Reduce Transparency on and off, and with the menu open.

## 2. SwiftUI `MenuBarExtra` or a hand-made `NSStatusItem`

- **The `MenuBarExtra` label cannot hold live layers.** The documentation covers only text, image and system-image labels, and it exposes no `NSStatusItem` ([MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)). Carbon's profile shows what a changing label costs: a SwiftUI graph update, then `setImage:` (which invalidates the button, so replicants refresh), then `_adjustLength`, then a CA commit. Each label change runs that whole chain **(inference from the profile and [BalanceBar#300](https://github.com/huanmeng06/BalanceBar/issues/300))**.
- **A SwiftUI view hosted in the button is no better.** Since macOS 26 such animations are reported choppy ([forum 803501](https://developer.apple.com/forums/thread/803501), [forum 839158](https://developer.apple.com/forums/thread/839158)). An Apple DTS engineer could not reproduce it, and there is no resolution. A hosting view is still a view tree that replicants re-snapshot.
- **Recommended: replace the `MenuBarExtra` scene with an `NSStatusItem` owned by the app delegate.** Its parts:
  - `statusItem.menu = NSHostingMenu(rootView: MenuBarMenu(model:updater:))` keeps the SwiftUI menu as it is ([NSHostingMenu](https://developer.apple.com/documentation/swiftui/nshostingmenu)). Apple says to use a `Group` or a multi-view top-level container, not an `HStack`.
  - `button.image` holds only static template content: the idle glyph, or the language badge while recording.
  - A meter subview sits inside the button.
  - `MenuBarExtra(isInserted:)` maps to `statusItem.isVisible`, plus `behavior = .removalAllowed` if the person should be able to remove it.
- **Two items cannot share one slot.** Keeping `MenuBarExtra` and adding a second `NSStatusItem` makes two separate menu bar items. Finding the `MenuBarExtra`'s button through `NSApp.windows` and adding a subview to it relies on private structure that SwiftUI can reset whenever it updates the label. Rejected.
- **(unverified) `@Environment(\.openSettings)` inside an `NSHostingMenu` that is not part of a `Scene`.** `MenuBarMenu` uses it. Check that Settings still opens. If it does not, pass in a closure.

## 3. Energy: timers, wakeups, frame rate

- **Timers wake the CPU.** Apple: "Timers prevent the CPU from going to or staying in the idle state". It recommends a tolerance of "at least 10 percent of the interval" and event-driven sources instead of polling ([Minimize Timer Usage](https://developer.apple.com/library/mac/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html)). Its general rules include "Don't poll for state changes, don't update content on the screen when the user can't see your app" and "make sure it races back to a zero-power idle state" ([Best Practices](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/BestPractices.html)).
- **Today's `Task.sleep(33 ms)` loop runs the main thread 30 times a second, even in silence.** The input only changes 10 times a second, so two wakeups in three can never show anything new **(inference from the code)**.
- **The level already arrives on the main actor 10 times a second.** Each tap buffer triggers `Task { @MainActor in self?.micLevel = level }`. Driving the layers from that hop adds no wakeup at all. This is the event-driven source Apple recommends.
- **`NSView.displayLink` (macOS 14+) does not help here.** It calls back "in-sync with the display the view is on", and not when the view is hidden or off-screen ([displayLink(target:selector:)](https://developer.apple.com/documentation/appkit/nsview/displaylink(target:selector:))). That is 60 to 120 callbacks a second, more than the 10 needed.
- **`CAAnimation` costs no app wakeups between updates.** The render server interpolates. `CAAnimation.preferredFrameRateRange` (macOS 12+) can cap the interpolation rate, for example to 30 fps ([docs](https://developer.apple.com/documentation/quartzcore/caanimation/preferredframeraterange)). WWDC21 notes that content slower than the display still costs power on fixed-rate displays ([Optimize for variable refresh rate displays](https://developer.apple.com/videos/play/wwdc2021/10147/)). The cheapest choice is **no interpolation**: discrete 10 Hz steps with actions disabled. Add a 100 ms animation only if the steps look too jumpy.
- **App Nap does not change anything here.** It applies to apps that are not foreground, have not "recently updated content in the visible portion of a window", and are not audible ([App Nap](https://developer.apple.com/library/content/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html)). A meter that keeps updating keeps Carbon out of App Nap. Apple also warns, "Don't rely on App Nap to get your app to fully idle". The design above has no timer for App Nap to throttle anyway.

## 4. Computing the level cheaply

- **Use `vDSP_rmsqv` (or `vDSP.rootMeanSquare`) for the RMS.** It replaces the scalar loop. It takes a stride, so it handles the `buffer.stride` case ([vDSP_rmsqv](https://developer.apple.com/documentation/accelerate/vdsp_rmsqv), [vDSP.rootMeanSquare](https://developer.apple.com/documentation/accelerate/vdsp/rootmeansquare(_:)-4mwg7)). A 100 ms buffer at 48 kHz is 4,800 samples, a few microseconds of vectorized work per buffer **(inference)**. The 2% measured for the RMS loop was a Debug build of the scalar loop.
- **Compute the RMS once per buffer.** Today `isSound` and `meter` each compute it.
- **AudioUnit metering is no cheaper.** `kAudioUnitProperty_MeteringMode` turns metering on for a scope ([docs](https://developer.apple.com/documentation/audiotoolbox/kaudiounitproperty_meteringmode)). You still have to poll a power parameter, on a mixer node Carbon does not have. That is more moving parts for a cost that is already negligible.
- **Keep the rate at about 10 Hz: one level per tap buffer.** `bufferSize` is only a request: "The implementation may choose another size" ([installTap](https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:))). If buffers arrive faster, keep the latest level and push to the main actor no more than about every 100 ms.
  - Aside: Apple's metadata lists `installTap` as available through macOS 27.0, which suggests it will be deprecated. That is outside this note's scope **(unverified)**.

## 5. Prior art and its measured cost

| App | Technique | Reported cost | Source |
|---|---|---|---|
| **MenuMeter** (2 stereo bars, gradient, peak hold) | `CALayer` frames moved on a 30 Hz `Timer` (10 Hz when silent), actions disabled, unchanged frames skipped. Replicas refreshed at 10 fps or 1 fps. | **~2% of a core at 30 fps, 3% at 60 fps**, "close to nothing" when silent. **~30%** when it redrew the view. | [README.md#L12, #L50](https://github.com/bassepeder/MenuMeter/blob/ea445f2d4fae9eb6f3da8953a0b0f94f5d3ee089/README.md#L50), [commit e3c18bb](https://github.com/bassepeder/MenuMeter/commit/e3c18bb) |
| **BalanceBar**, bitmap per frame (30 fps `setImage:`) | New `NSImage` per tick | 18–25% CPU, against 1–5% with the animation off | [#300](https://github.com/huanmeng06/BalanceBar/issues/300) |
| **BalanceBar**, custom view tree in the button | Replicant re-snapshot loop | 50–60%+ CPU spikes, about 333–365 `_updateReplicants`/s | [#284](https://github.com/huanmeng06/BalanceBar/issues/284) |
| **BalanceBar**, Core Animation path (shipped default) | `CAKeyframeAnimation` on an owned sublayer | Main thread about 99.25% waiting, paused on non-active displays | [PR #304](https://github.com/huanmeng06/BalanceBar/pull/304) |
| Control Center mic indicator, Voice Memos, Dictation | Not documented | — | **(unverified)**. I found no Apple source on how they draw meters or what that costs. |

The 18–25% that BalanceBar measured for 30 fps `setImage:` matches Carbon's 18%. Carbon is paying the known cost of image swapping, not a cost of its own making.

## Recommended design

1. **Status item**: `NSStatusBar.system.statusItem(withLength:)` with a fixed length. While recording, the length covers the meter plus the badge. Change it only when the state or the badge text changes, never while the bars move.
2. **Static content goes in `button.image` as one template image**: the idle glyph, or the badge while recording. Build it once per change, never per frame. This keeps template tinting for everything except the bars.
3. **Meter view**: an `NSView` subview of the button with `wantsLayer = true` and `hitTest` returning `nil`. It holds three `CALayer` bars, 2 pt wide with a 1 pt corner radius, matching today's geometry.
   - A level update sets each bar's `bounds.height`, or `frame`, inside `CATransaction.begin(); setDisableActions(true) … commit()`.
   - Heights are rounded to half points. If nothing changed, return before opening a transaction. In silence that means no commits at all.
   - Never set `needsDisplay`, never draw, never touch `button.image`.
4. **Feed**: call `meterView.show(level)` from the existing `@MainActor` hop in `Recorder.capture`, or from an observer of `micLevel`, but not through a SwiftUI view.
   - Keep the outward ripple with a three-slot history, one slot per 100 ms buffer.
   - Rise fast and fall slowly by easing the target over one or two updates, not with a timer.
   - Delete the `.task` loop.
5. **Appearance**: resolve the bar color in `viewDidChangeEffectiveAppearance` with `performAsCurrentDrawingAppearance { NSColor.labelColor.cgColor }`. Use `.selectedMenuItemTextColor` while the menu is open, if the highlight needs it **(unverified on Tahoe)**.
6. **Replicas**: either accept frozen bars on secondary displays, as BalanceBar does, or copy MenuMeter. Every 0.5 s, and once when the level falls to silence, set `needsDisplay`, but only while another `NSStatusBarWindow` intersects a screen. Each refresh is a CPU snapshot with a blurred shadow, so keep it rare.
7. **Level**: one `vDSP_rmsqv` per channel per buffer, shared by `isSound` and `meter`.
8. **Reduce Motion**: when `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` is on, show a static recording glyph.
9. **Menu**: `statusItem.menu = NSHostingMenu(rootView: MenuBarMenu(…))`. Remove the `MenuBarExtra` scene.

### Estimated cost (Release build, during a recording)

| Part | Today | Recommended design |
|---|---|---|
| Carbon main thread | ~18% of a core (measured, Debug) | **≲1%** **(inference)**: 10 commits/s of three layer frames, against MenuMeter's ~2% at 30/s with 10 layers. No SwiftUI, no `setImage:`, no `_adjustLength`. |
| Audio thread RMS | ~2% (Debug, scalar loop) | negligible **(inference)** |
| Replicant snapshots | each `setImage:` | none on one display. With option 6, 2/s while another display shows the item. |
| WindowServer | ~17% | **(unverified)**. Discrete 10 Hz layer changes should cost far less than 30 replaced images a second with relayout, but nothing documents the number. |
| Wakeups added | 30/s main-thread timer | 0 (rides the existing 10 Hz audio hop) |

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Keep `MenuBarExtra`; swap images at 10 Hz, cache the badge, fix the width | Still runs SwiftUI update → `setImage:` → replicant refresh → length check → commit each time. Perhaps a third of today's cost, several percent of a core **(inference)**, not "almost painless". |
| `NSHostingView` with SwiftUI shapes inside the button | Reported choppy on macOS 26 ([forum 803501](https://developer.apple.com/forums/thread/803501)). Still a view tree that replicants re-snapshot. Still runs SwiftUI's graph per change. |
| Custom `draw(_:)` view in the button | Every redraw re-renders all replicas on the CPU. MenuMeter measured ~30% this way ([commit e3c18bb](https://github.com/bassepeder/MenuMeter/commit/e3c18bb)). |
| `NSView.displayLink` / `CADisplayLink` driver | 60–120 callbacks/s ([docs](https://developer.apple.com/documentation/appkit/nsview/displaylink(target:selector:))) to show 10 Hz data |
| Continuous `CAKeyframeAnimation` (fake "voice" wiggle that is not driven by the level) | Costs nothing in the app ([BalanceBar PR #304](https://github.com/huanmeng06/BalanceBar/pull/304)), but it no longer tells the person the mic hears them, which is the point of the feature. Still a fallback if live data turns out too costly. |
| Two status items (keep `MenuBarExtra` and add a meter item) | Two separate menu bar items, and the HIG warns against relying on how extras are placed ([HIG](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)) |
| AudioUnit metering properties | No cheaper than `vDSP` on a buffer the tap already delivers, and Carbon has no mixer node to meter |

## How to check before keeping it

Use a Release build, one display, during a recording. Compare the meter on against the meter replaced by a static recording glyph, so the difference is the meter alone:

1. `sample Carbon 10`, then count `setImage:`, `_adjustLength`, `_updateReplicantsUnlessMenuIsTracking`, `_redrawReplicantSnapshot` and `CA::Transaction::commit`. The first four should be close to 0. Commits should be at most about 10 per second.
2. `top -l 30 -s 1 -stats pid,command,cpu -pid <WindowServer pid>` and the same for Carbon, in both configurations. Read the difference.
3. Repeat with a second display connected, to price the replica refresh in step 6.
4. Activity Monitor › Energy, "Energy Impact" and "Preventing Sleep", in both configurations.

**Keep the feature only if the meter adds no more than about 1–2% of one core across Carbon and WindowServer combined.** That threshold is my proposal, not an Apple figure. If it costs more, drop it, or fall back to the level-independent animation from the alternatives.

## Measured after the change (2026-10-30)

Debug build, one display, a machine also running several headless Chrome processes, so WindowServer readings carry about ±10% of noise.

- **Carbon during a recording**: about 1.3% of a core in total, transcription included, against about 19% with the `MenuBarExtra` label. The main thread was busy 0.5% of the samples.
- **WindowServer, isolated with a test status item** driving three layers from random levels at 10 Hz, two rounds each:
  - **Implicit Core Animation tweens (0.1 s up, 0.25 s down): about +14%** over no item, in both rounds. A tween makes WindowServer redraw the menu bar at the display's refresh rate for as long as the levels keep changing.
  - **Jumps with actions disabled, at 10, 20 or 30 Hz**: no difference that stood out of the noise.
- **Decision**: the bars jump to each level with actions disabled, as MenuMeter does, and fall at most by half a level per update to read smoothly. Not yet measured: a Release build, a second display, Activity Monitor's Energy Impact.
