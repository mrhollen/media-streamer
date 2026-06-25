# Stream Viewer Screen Specification

## Summary

This document details the UI/UX specification for the Stream Viewer screen, the primary screen of the Media Streamer app where video and audio streams are displayed. It covers layout, interactions, states, and behavior.

## Table of Contents

- [Overview](#overview)
- [Layout](#layout)
- [States](#states)
- [Interactions](#interactions)
- [Behavior](#behavior)
- [Audio-Specific Design](#audio-specific-design)

---

## Overview

The Stream Viewer screen is the main interaction point of the app. It displays live video or audio streams from devices on the network with minimal UI chrome.

**Purpose:** Display live video/audio streams, provide stream control.

**Navigation:** Pushed on top of Device List

---

## Layout

### Full-Screen Video Stream

**Design:**
- **NO visible app bar or chrome by default**
- Stream fills the entire screen
- Video maintains aspect ratio (letterbox with black bars or crop)
- Dark theme overlays

**Video Rendering:**
- Aspect ratio preserved
- Letterbox recommended (maintain aspect, black bars)
- Full-screen capability (expand to cover screen)
- Video controls hidden (custom controls only)

### Controls Overlay

**Visibility:**
- Hidden by default
- Appears on first tap
- Auto-hides after 3 seconds of inactivity (no taps)

**Layout:**

```
┌─────────────────────────────────┐
│  [Back]  Device Name  Server    │  ← Top area
│                                 │
│                                 │
│         [Stream Area]           │
│                                 │
│                                 │
│           [Device Type]         │
│           [Stop]                 │  ← Bottom area
└─────────────────────────────────┘
```

**Top Area:**
- **Back button:** Top-left corner (Material back icon)
- **Device name:** Centered, 16sp, white text
- **Server name:** Right-aligned, 14sp, muted text

**Bottom Area:**
- **Device type indicator:** "Video" or "Audio" (centered, small text)
- **Stop button:** Centered, large button (X icon or "Stop")

**Button Styles:**
- Back button: Icon only, no background
- Stop button: Circular button, primary color background
- All text: White, high contrast

### Connecting State

**Layout:**
- Full-screen centered
- Minimal spinner/progress indicator
- Text: "Connecting..."

**Behavior:**
- No controls overlay
- Tap to advance or cancel

### Error State

**Layout:**
- Centered error card
- Card has slight elevation
- Icon (error/warning)
- Device name
- Error message (brief, 1-2 lines)
- "Retry" button (primary style)

**Behavior:**
- Tap card to dismiss (briefly)
- Tap "Retry" to re-attempt connection

### Disconnected State

**Layout:**
- Same as error state
- Text: "Connection lost"
- Optional: Last disconnected time

**Behavior:**
- Tap "Reconnect" to re-attempt connection

---

## States

### State Machine

```
┌─────────────┐     connect     ┌─────────────┐
│   Idle      │ ─────────────>  │ Connecting  │
└─────────────┘                 └─────────────┘
       │                              │
       │ cancel                        │ success
       └───────────────────────────────┘
                                        │
                                        ▼
                                  ┌─────────────┐
                                  │   Playing   │
                                  └─────────────┘
                                        │
                                        │
                                        ▼
                                        ┌─────────────┐
                                        │    Error    │
                                        └─────────────┘
                                        │
                                        ▼
                                        ┌─────────────┐
                                        │ Disconnected│
                                        └─────────────┘
```

### State Details

| State | Trigger | UI |
|-------|---------|-----|
| **Idle** | Screen load, no stream | Empty screen or minimal placeholder |
| **Connecting** | WebSocket connection initiated | Centered spinner + "Connecting..." |
| **Playing** | Stream active | Full-screen stream, tap-to-reveal controls |
| **Error** | Connection failed (auth, network, etc.) | Error card with retry button |
| **Disconnected** | Stream closed unexpectedly | Error card with reconnect button |

---

## Interactions

### Tap Anywhere (Playing State)

**Trigger:** Tap on stream area

**Action:** Toggle controls overlay visibility

**Behavior:**
- If controls hidden: Show controls overlay
- If controls visible: Hide controls overlay (after 3s timeout)

### Swipe Down from Top

**Trigger:** Swipe gesture starting from top edge

**Action:** Navigate to Device List, stop stream

**Behavior:**
- Animate controls out of view
- Pop Stream Viewer from navigation stack
- Close WebSocket connection
- Return to Device List

### Back Button

**Trigger:** Tap back icon in controls overlay

**Action:** Same as swipe down

**Behavior:**
- Navigate to Device List
- Stop stream
- Close WebSocket

### Stop Button

**Trigger:** Tap stop button

**Action:** Stop stream, navigate to Device List

**Behavior:**
- Close WebSocket connection
- Pop Stream Viewer from stack
- Return to Device List

### Retry Button (Error State)

**Trigger:** Tap retry button

**Action:** Re-attempt WebSocket connection

**Behavior:**
- Show Connecting state
- If successful: Return to Playing state
- If failed: Update error message

### Reconnect Button (Disconnected State)

**Trigger:** Tap reconnect button

**Action:** Same as retry button

**Behavior:**
- Re-establish WebSocket connection
- Show Connecting state

---

## Behavior

### Stream Lifecycle

**On Enter (Stream Viewer pushed):**
1. Show Connecting state
2. Initiate WebSocket connection
3. Send PSK authentication (first message)
4. On success: Show stream, hide controls after 3s

**On Exit (User navigates back):**
1. Close WebSocket connection
2. Stop stream
3. Pop from navigation stack
4. Return to Device List

**On Disconnect (Stream closes unexpectedly):**
1. Show Disconnected/Error state
2. Keep user on screen (don't navigate away)
3. Wait for user action (retry/reconnect)

### WebSocket Connection

**Authentication:**
- First message: PSK as text frame
- Subsequent messages: Binary frames (H.264 or Opus)

**Timeouts:**
- Connection timeout: 10 seconds
- Auth timeout: 10 seconds
- Heartbeat: Optional (ping/pong)

**Error Handling:**
- 401: Invalid PSK → Error state
- 404: Device not found → Error state
- 500: Server error → Error state
- Network error → Disconnected state

### Controls Auto-Hide

**Timer:** 3 seconds of inactivity

**Reset on:**
- User tap
- Stream interaction (play/pause if applicable)

**Hide on:**
- No user interaction for 3 seconds
- Navigate away

---

## Audio-Specific Design

### Audio Stream Layout

**Layout:**
- Centered device name (16sp, white)
- Large play/stop button (80x80dp, circular)
- Subtle audio level visualization

**Audio Visualization:**
- Position: Below device name, above stop button
- Style: Animated bars or waveform
- Height: 32dp
- Color: Primary accent color (low opacity)
- Animation: Smooth, responsive to audio levels

**Button Behavior:**
- Play state: Button shows pause icon
- Stop state: Button shows stop icon (X)
- Tap: Toggle play/stop

### Video vs Audio

| Element | Video | Audio |
|---------|-------|-------|
| Main content | Full-screen video | Centered controls |
| Aspect ratio | Letterbox/crop | N/A |
| Controls position | Overlay | Centered |
| Visualization | None | Audio levels |
| Back button | Top-left | Top-left |

---

## Design Tokens

### Colors

```
Background: #000000 (black - for video)
Overlay Background: rgba(0, 0, 0, 0.5)
Surface: #1E1E1E
Primary: #6200EE (accent)
Secondary: #03DAC6
Error: #B00020
Success: #4CAF50
Text: #FFFFFF
Text Muted: #B0B0B0
```

### Typography

```
Device Name: 16sp (Roboto Medium)
Server Name: 14sp (Roboto Regular)
Type Label: 12sp (Roboto Regular)
Error Message: 14sp (Roboto Regular)
```

### Spacing

```
Controls top margin: 16dp
Controls bottom margin: 16dp
Controls horizontal padding: 24dp
Stop button size: 64dp diameter
Audio visualization height: 32dp
```

### Animation

```
Controls fade in/out: 200ms ease-in-out
Swipe transition: 300ms ease-out
Error card slide in: 200ms ease-out
```

---

## Accessibility

- **Touch targets:** Minimum 48x48dp for interactive elements
- **Contrast:** WCAG AA compliant for all text
- **Screen reader:**
  - Announce stream type (video/audio)
  - Announce device name
  - Announce connection state changes
  - Announce errors
- **Video playback:** Provide pause/play controls (if applicable)
- **Audio levels:** Provide alternative text representation

---

## Implementation Notes

- Use `VideoPlayer` package for video playback
- Use `audio_level` package for audio visualization
- Implement custom controls overlay (don't use system controls)
- Use `GestureDetector` for tap detection
- Use `WillPopScope` for back button handling
- WebSocket managed by `StreamProvider`
- Stream lifecycle hooks: `onEnter`, `onExit`
- Consider using `Stack` for layering stream and controls
