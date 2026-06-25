# Device List Screen Specification

## Summary

This document details the UI/UX specification for the Device List screen, displayed when navigating from a server in the Server List. It covers layout, interactions, states, and behavior.

## Table of Contents

- [Overview](#overview)
- [Layout](#layout)
- [Interactions](#interactions)
- [States](#states)
- [Navigation](#navigation)

---

## Overview

The Device List screen displays all available AV devices (webcams, microphones) from a selected server. It serves as the bridge between server selection and stream viewing.

**Purpose:** Display available devices from a selected server, allow navigation to stream viewer.

**Navigation:** Pushed on top of Server List

---

## Layout

### App Bar

**Elements (left to right):**
- **Back button:** Standard Material back icon
- **Server name:** Title text (derived from parent server)
- **Connection status dot:** Circular indicator

**Status Dot Colors:**
- `Green (#4CAF50)` — connected
- `Amber (#FF9800)` — connecting
- `Gray (#9E9E9E)` — offline

**Behavior:**
- Back button navigates to Server List and stops current stream
- Status dot reflects real-time connection status

### Body Content

**Device Rows List**

- **Scroll behavior:** Vertically scrollable
- **Row design:**
  - Clean, minimal appearance
  - Subtle dividers between rows
  - Dark theme background
  - Full width, appropriate padding

**Row Content:**

| Element | Description |
|---------|-------------|
| Type Icon | Visual indicator (camera for video, speaker for audio) |
| Device Name | From server API (e.g., "Logitech C920") |
| Type Label | Text label "Video" or "Audio" |

**Icon Mapping:**
- Video device: Camera icon (`mdi:camera` or `flutter_icon:camera`)
- Audio device: Speaker icon (`mdi:volume-high` or `flutter_icon:volume-high`)

### Empty State

**Trigger:** No devices available from server

**Layout:**
- Centered vertically and horizontally
- Icon (device/offline icon)
- Text: "No devices available"
- "Refresh" button (secondary style)

---

## Interactions

### Pull-to-Refresh

**Trigger:** User performs swipe-down gesture on list

**Action:** Re-fetches device list from server

**Feedback:**
- Standard refresh animation
- Brief loading indicator while fetching
- Device rows update with new data

### Tap Device Row

**Trigger:** Tap gesture

**Action:** Pushes Stream Viewer screen

**Behavior:**
- Device List remains in stack (can navigate back)
- Stream Viewer is pushed on top
- WebSocket connection initiated to device stream
- Loading state shown during connection

### Long-Press on Device Row

**Trigger:** Long-press gesture (approx. 500ms)

**Action:** Opens context menu

**Menu Options:**
- **Copy device ID:** Copies device ID to clipboard

**Dismiss:** Tap outside menu or swipe down

### Click App Bar Back Button

**Trigger:** Tap back icon

**Action:** Navigate to Server List

**Behavior:**
- Pops Device List from navigation stack
- Stream Viewer (if open) is also popped
- WebSocket connection is closed

---

## States

### Loading State

**Trigger:** Initial load or pull-to-refresh

**Design:**
- Skeleton rows with shimmer animation
- Same height as real device rows
- Alternating opacity to simulate loading
- Icons and text placeholders

### Error State (Server Offline)

**Trigger:** Server unreachable

**Design:**
- Banner at top of screen
- Icon: Server warning/error
- Text: "Server is offline"
- Action: "Reconnect" button

**Device Rows Behavior:**
- All rows appear dimmed (reduced opacity)
- Rows are disabled (tapping has no effect)
- Status dot shows gray/offline

**Reconnect Action:**
- "Reconnect" button attempts to re-establish connection
- On success: Device rows re-enable, status updates to green
- On failure: Banner remains, device rows stay disabled

### Error State (Connection Failed)

**Trigger:** Individual device connection fails

**Design:**
- Inline error message on device row
- "Retry" button (small, secondary style)
- Row remains enabled for retry

---

## Navigation

### Navigation Stack

```
┌─────────────────┐
│   Stream Viewer │  ← Top (if open)
├─────────────────┤
│   Device List   │  ← Current screen
├─────────────────┤
│  Server List    │  ← Parent (visible when back)
└─────────────────┘
```

### Navigation Actions

| Action | Result |
|--------|--------|
| Tap device row | Push Stream Viewer |
| Tap back button | Pop to Server List |
| Tap FAB | Open QR Scanner (if enabled) |
| Swipe down (refresh) | Re-fetch devices |

### Back Behavior

- Tapping back from Device List always navigates to Server List
- Stream Viewer (if open) is automatically closed
- WebSocket connection is terminated

---

## Design Tokens

### Colors

```
Background: #121212 (Material dark)
Surface: #1E1E1E
Card: #2C2C2C
Primary: #6200EE (accent)
Secondary: #03DAC6
Error: #B00020
Success: #4CAF50
Warning: #FF9800
Disabled: #424242
```

### Typography

```
Title: 20sp (Roboto Bold) — Server name
Subtitle: 14sp (Roboto Regular) — Device name
Caption: 12sp (Roboto Regular) — Type label
```

### Spacing

```
Row padding: 16dp horizontal, 12dp vertical
Row height: 64dp
Icon size: 24x24dp
Divider height: 8dp
Status dot size: 12dp diameter
```

### Elevation

```
Row elevation: 1dp (subtle)
Active row elevation: 2dp (on tap)
```

---

## Accessibility

- **Touch targets:** Minimum 48x48dp for device rows
- **Icons:** Include accessibility labels (e.g., "Camera: Front Camera")
- **Contrast:** WCAG AA compliant for all text
- **Screen reader:** 
  - Announce device names and types
  - Announce connection status changes
  - Announce error messages

---

## Implementation Notes

- Use `ListView.builder` for efficient rendering
- Implement pull-to-refresh with `RefreshIndicator`
- Use `GestureDetector` for tap and long-press
- Device rows use `InkWell` for ripple feedback
- Connection state managed by `ServerProvider`
- Context menu uses `showMenu` or custom bottom sheet
- WebSocket connection initiated by `StreamProvider`
