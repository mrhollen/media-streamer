# Server List Screen Specification

## Summary

This document details the UI/UX specification for the Server List screen, the root/home screen of the Media Streamer mobile app. It covers layout, interactions, states, and behavior.

## Table of Contents

- [Overview](#overview)
- [Layout](#layout)
- [Interactions](#interactions)
- [States](#states)
- [Mini-Player Integration](#mini-player-integration)

---

## Overview

The Server List screen is the entry point of the application. It displays a list of saved media streaming servers, allowing users to view connection status and navigate to device lists.

**Purpose:** Display saved servers, show connection status, provide navigation to device lists.

**Navigation:** Root screen (no back navigation)

---

## Layout

### App Bar

- **Title:** "Media Streamer" (left-aligned)
- **Trailing actions:** None
- **Style:** Standard Material app bar, dark theme

### Body Content

**Server Cards List**

- **Scroll behavior:** Vertically scrollable
- **Card design:**
  - Subtle elevation (elevation: 2dp)
  - Rounded corners (borderRadius: 8-12dp)
  - Full width, appropriate padding
  - Dark theme background

**Card Content:**

| Element | Description |
|---------|-------------|
| Server Name | User-assigned name, or IP address if unnamed |
| Status Dot | Circular indicator showing connection status |
| Device Count | Badge showing number of available devices |

**Status Dot Colors:**
- `Green (#4CAF50)` — connected
- `Amber (#FF9800)` — connecting
- `Gray (#9E9E9E)` — offline

### Empty State

**Trigger:** No servers in the list

**Layout:**
- Centered vertically and horizontally
- Icon (server/add icon)
- Text: "No servers yet"
- Prominent "Add Server" button (primary action)

### Floating Action Button (FAB)

**Position:** Bottom-right corner

**Design:**
- Icon: "+"
- Color: Primary color (accent)
- Behavior: Opens QR Scanner modal

### Mini-Player Pill

**Position:** Bottom of screen, above FAB area

**Visible when:** A stream is active (from any server)

**Content:**
- Device name
- Server name
- Play/pause indicator
- Stop button (X icon)

**Behavior:**
- Tapping navigates to Stream Viewer
- Tapping stop button closes mini-player (stream continues in background)

---

## Interactions

### Pull-to-Refresh

**Trigger:** User performs swipe-down gesture on list

**Action:** Re-checks connection status of all servers

**Feedback:**
- Standard refresh animation
- Brief loading indicator while checking

### Long-Press on Server Card

**Trigger:** Long-press gesture (approx. 500ms)

**Action:** Opens context menu

**Menu Options:**
- **Rename:** Opens dialog to edit server name
- **Remove:** Deletes server from list (with confirmation)

**Dismiss:** Tap outside menu or swipe down

### Tap Server Card

**Trigger:** Tap gesture

**Action:** Pushes Device List screen

**Behavior:**
- Server List remains in stack (can navigate back)
- Device List is pushed on top

### Tap FAB

**Trigger:** Tap gesture

**Action:** Presents QR Scanner modal

**Behavior:**
- Modal takes full screen (or adaptive layout)
- Camera activates
- Dismisses via cancel or successful scan

---

## States

### Loading State

**Trigger:** Initial load or pull-to-refresh

**Design:**
- Skeleton cards with shimmer animation
- Same height/width as real cards
- Alternating opacity to simulate loading

### Error State (Network)

**Trigger:** No network connection

**Design:**
- Banner at top of screen
- Icon: Network warning/error
- Text: "No network connection"
- Action: "Retry" button

**Behavior:**
- Banner is dismissible
- "Retry" re-attempts network check

### Error State (Server Offline)

**Trigger:** Specific server unreachable

**Design:**
- Server card shows gray status dot
- No special banner (per design principle: inline errors)

---

## Mini-Player Integration

### Activation

**When:** A stream is playing (from any server)

**How:**
- ServerProvider detects active stream
- Renders mini-player pill at bottom of Server List
- Pill is non-intrusive, doesn't block FAB

### Deactivation

**When:** Stream is stopped or user navigates away

**How:**
- ServerProvider detects stream closure
- Mini-player pill disappears

### Mini-Player Actions

| Action | Result |
|--------|--------|
| Tap pill area | Navigate to Stream Viewer (full screen) |
| Tap stop button | Close mini-player only |
| Swipe down on pill | Close mini-player |

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
```

### Typography

```
Title: 24sp (Roboto Bold)
Subtitle: 16sp (Roboto Regular)
Body: 14sp (Roboto Regular)
Caption: 12sp (Roboto Regular)
```

### Spacing

```
Card padding: 16dp horizontal, 12dp vertical
FAB margin: 16dp from edges
Mini-player height: 48dp
Status dot size: 12dp diameter
```

---

## Accessibility

- **Touch targets:** Minimum 48x48dp for interactive elements
- **Status dots:** Include accessibility labels ("Connected", "Connecting", "Offline")
- **Contrast:** WCAG AA compliant for all text
- **Screen reader:** Announce server names and status changes

---

## Implementation Notes

- Use `ListView.builder` for efficient rendering
- Implement pull-to-refresh with `RefreshIndicator`
- Use `GestureDetector` for long-press detection
- Mini-player state managed by `ServerProvider`
- Context menu uses `showMenu` or custom bottom sheet
