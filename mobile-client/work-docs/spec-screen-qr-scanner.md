# QR Scanner Screen Specification

## Summary

This document details the UI/UX specification for the QR Scanner screen, presented as a full-screen modal dialog from the Server List. It covers layout, flow, and error handling.

## Table of Contents

- [Overview](#overview)
- [Layout](#layout)
- [Flow](#flow)
- [Manual Entry Mode](#manual-entry-mode)
- [Error Handling](#error-handling)

---

## Overview

The QR Scanner screen allows users to quickly add servers by scanning a QR code. It is presented as a modal dialog from the Server List's floating action button (FAB).

**Purpose:** Add new servers via QR code scanning or manual entry.

**Trigger:** Tap FAB on Server List screen

**Dismissal:** Cancel button, successful scan, or timeout

---

## Layout

### Camera Preview

**Design:**
- Fills the entire screen (minus UI elements)
- Live camera preview
- Dark theme overlay

### Scanning Overlay

**Position:** Centered

**Design:**
- Rounded rectangle with corner brackets
- Corner brackets: Thin lines (2-4dp) at each corner
- Background: Transparent or semi-transparent
- Color: Primary accent color (60% opacity)

**Purpose:** Guide user where to aim camera

### Instruction Text

**Position:** Above scanning overlay

**Content:** "Point your camera at the QR code"

**Style:**
- Centered
- 14sp, white text
- Max 2 lines, ellipsis if needed

### Cancel Button

**Position:** Top-left corner

**Design:**
- Text button (no icon)
- White text
- 48x48dp touch target

**Behavior:** Closes scanner without saving

### Manual Entry Link

**Position:** Bottom of screen

**Design:**
- Text link style
- "Enter manually"
- Optional: Arrow icon →
- Tap opens manual entry form

---

## Flow

### Scanner Mode

**Step 1: Open**
- User taps FAB on Server List
- Scanner modal opens (full-screen)
- Camera activates
- Permission prompt shown if first time

**Step 2: Scanning**
- Camera preview active
- Scanning overlay visible
- User positions camera on QR code
- Real-time scanning feedback (optional: flash when code detected)

**Step 3: Detection**
- QR code detected and parsed
- Camera freezes (preview stops updating)
- Confirmation card slides up from bottom

**Step 4: Confirmation**
- Card shows:
  - Server address (e.g., "192.168.1.100:8080")
  - TLS indicator (lock icon if TLS fingerprint present)
  - "Connecting..." state
- User can:
  - Wait for auto-connection
  - Tap "Cancel" to retry

**Step 5: Result**

**Success:**
- Card shows "Connected"
- Modal dismisses automatically
- Server added to Server List
- Device List pushed for new server

**Failure:**
- Card shows error message
- Buttons: "Try Again", "Cancel"
- User can retry or cancel

### Manual Entry Mode

**Step 1: Switch to Manual**
- User taps "Enter manually" link
- Camera preview hides
- Manual entry form appears (slides up or replaces camera)

**Step 2: Fill Form**
- Server Address (required)
- PSK (required)
- TLS Fingerprint (optional)

**Step 3: Save & Connect**
- User taps "Save & Connect" button
- Form validates
- Connection test initiated
- Loading indicator shown

**Step 4: Result**

**Success:**
- Success message shown
- Server added to list
- Device List pushed

**Failure:**
- Error message shown
- Form remains for correction

---

## Manual Entry Mode

### Form Fields

**Server Address**
- Type: Text input
- Placeholder: "192.168.1.100:8080"
- Required: Yes
- Validation: Must contain address and port

**PSK (Pre-Shared Key)**
- Type: Secure text input (password style)
- Placeholder: "Enter PSK"
- Required: Yes
- Validation: Minimum 8 characters
- Show/hide password toggle

**TLS Fingerprint**
- Type: Text input
- Placeholder: "SHA-256 fingerprint (optional)"
- Required: No
- Validation: Optional, if provided must be valid hex

### "Save & Connect" Button

**Position:** Bottom of form

**Design:**
- Primary button style
- Full width
- Minimum height 48dp

**Behavior:**
- Validates form
- Shows loading state during connection
- On success: Add server, navigate to Device List
- On failure: Show error message

---

## Error Handling

### Camera Permission Denied

**Trigger:** User denies camera permission

**UI:**
- Full-screen overlay (replaces camera preview)
- Icon: Camera with lock
- Text: "Camera access is required to scan QR codes"
- Buttons: "Open Settings", "Cancel"

**"Open Settings" Action:**
- Opens device settings app
- User can grant permission
- Returns to scanner

### Invalid QR Code

**Trigger:** QR code cannot be parsed

**UI:**
- Brief inline message at top of preview
- Text: "Could not read server details"
- Auto-dismiss after 2 seconds

**Behavior:**
- Scanning continues
- User can try another code

### Connection Failed

**Trigger:** Server unreachable or invalid credentials

**UI:**
- Confirmation card shows error message
- Clear, user-friendly message
- Buttons: "Try Again", "Cancel"

**Examples:**
- "Server not responding"
- "Invalid PSK"
- "TLS certificate mismatch"

### Form Validation Errors

**Trigger:** Invalid input on "Save & Connect"

**UI:**
- Inline error message under field
- Red text
- Field border turns red

**Examples:**
- "Server address is required"
- "PSK must be at least 8 characters"
- "Invalid port number"

---

## Modal Design

### Presentation

**Type:** Full-screen modal (showModalBottomSheet with expand: true)

**Dismissal:**
- Tap outside (if using bottom sheet)
- Tap cancel button
- Successful scan
- Timeout (optional: 60 seconds)

### Transitions

**Open:** Slide up from bottom (300ms)
**Close:** Slide down (200ms)
**Confirmation card:** Slide up from bottom (200ms)

---

## Design Tokens

### Colors

```
Background: #000000 (black)
Surface: #1E1E1E
Primary: #6200EE (accent)
Secondary: #03DAC6
Error: #B00020
Success: #4CAF50
Overlay: rgba(0, 0, 0, 0.8)
```

### Typography

```
Instruction: 14sp (Roboto Regular)
Button: 16sp (Roboto Medium)
Error: 14sp (Roboto Regular)
```

### Spacing

```
Top margin: 48dp (for instruction)
Bottom margin: 16dp (for manual link)
Touch targets: 48x48dp minimum
```

### Animation

```
Modal slide: 300ms ease-out
Card slide: 200ms ease-out
Fade: 200ms ease-in-out
```

---

## Implementation Notes

- Use `camera` package for QR scanning
- Use `qr_code_scanner` package for decoding
- Use `showModalBottomSheet` for modal presentation
- Camera preview uses `CameraController`
- Confirmation card uses `AnimatedContainer` or `SlideTransition`
- Manual entry form uses `SingleChildScrollView`
- Form validation with custom `TextEditingController` logic
- Permission handling with `PermissionHandler` package
