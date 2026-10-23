# Feature Specification: Screenshot Capture & Annotation

**Feature Branch**: `001-screenshot-capture-annotation`

**Created**: 2026-10-23

**Status**: Draft

**Input**: User description: "I want a native macos version of snagit clone, use swift to write and xcode project. No need recording feature but screenshot capturing and annotation funciton are must to have."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Capture a Screenshot (Priority: P1)

A user presses a global shortcut (or uses the menu bar icon) and captures part or all of their screen: a dragged region, a single window, or a full display. The captured image is immediately available to them, opened in the editor and also on the clipboard if they chose that option, with no extra steps.

**Why this priority**: Capture is the entry point to everything else. On its own it already delivers value as a screenshot utility.

**Independent Test**: Trigger each capture mode (region, window, full screen) and confirm that an image matching what was on screen appears in the editor and can be saved or copied.

**Acceptance Scenarios**:

1. **Given** the app is running in the background, **When** the user presses the capture shortcut and drags a rectangle, **Then** the selected region is captured at the display's native resolution and opened in the editor.
2. **Given** the user is in capture mode, **When** they hover over a window and click, **Then** only that window is captured, including its title bar.
3. **Given** the user is in capture mode, **When** they choose full screen on a multi-display setup, **Then** the display under the pointer is captured.
4. **Given** the user is in capture mode, **When** they press Escape, **Then** capture is cancelled and nothing is saved or copied.
5. **Given** screen capture permission has not been granted, **When** the user attempts a capture, **Then** the app explains what is missing and guides them to grant it, instead of producing a blank or empty image.

---

### User Story 2 - Annotate a Capture (Priority: P1)

After capturing, the user marks up the image in an editor window. They add arrows, rectangles, ellipses, lines, text labels, numbered step markers, and a highlighter. They can blur or pixelate sensitive areas. They can select, move, resize, restyle (color, thickness, font size), reorder, and delete any annotation after placing it, and undo or redo any change.

**Why this priority**: Annotation is the other must-have named in the request and is what separates this app from the built-in macOS screenshot tool.

**Independent Test**: Open any image in the editor, add one of each annotation type, edit and delete some of them, use undo and redo, and confirm the edits behave as expected.

**Acceptance Scenarios**:

1. **Given** an image is open in the editor, **When** the user picks the arrow tool and drags on the image, **Then** an arrow appears from the start point to the end point in the chosen color and thickness.
2. **Given** an annotation exists, **When** the user selects it, **Then** handles appear and they can move, resize, recolor, or delete it without affecting the underlying image or other annotations.
3. **Given** the user applied a blur to a region, **When** they export the image, **Then** the original pixel content under the blur cannot be recovered from the exported file.
4. **Given** the user has made several edits, **When** they undo repeatedly, **Then** each edit is reverted in reverse order, and redo restores them.
5. **Given** the user picks the step-marker tool, **When** they click several times on the image, **Then** markers are placed with automatically increasing numbers.
6. **Given** the user picks the text tool, **When** they click and type, **Then** the text appears on the image and remains editable until finalized.

---

### User Story 3 - Save, Copy, and Share the Result (Priority: P2)

The user finishes editing and gets the image out of the app: copy to the clipboard, save to a file (PNG, JPEG), drag it into another app, or use the standard macOS share options.

**Why this priority**: Capturing and annotating only pays off if the result is easy to use elsewhere, but a user can still get value from P1 stories using a basic save.

**Independent Test**: Annotate an image, then copy it and paste it into another app, save it as PNG and as JPEG, and drag it into a chat or document window.

**Acceptance Scenarios**:

1. **Given** an annotated image, **When** the user chooses Copy, **Then** pasting into another app inserts the image with all annotations flattened into it.
2. **Given** an annotated image, **When** the user chooses Save and picks PNG or JPEG, **Then** a file is written with the annotations included.
3. **Given** an annotated image, **When** the user drags it from the editor to another app, **Then** the image is delivered to that app.
4. **Given** an annotated image, **When** the user opens the share menu, **Then** the standard macOS sharing destinations are offered.

---

### User Story 4 - Return to Earlier Captures (Priority: P2)

The user can find recent captures in a library and reopen them to keep annotating. Annotations stay editable (not flattened) until the user exports.

**Why this priority**: It turns the app from a one-shot tool into a working tool, but is not required for the first useful release.

**Independent Test**: Capture and annotate an image, close the editor, quit and relaunch the app, then reopen the capture from the library and confirm the annotations are still individually editable.

**Acceptance Scenarios**:

1. **Given** the user has made several captures, **When** they open the library, **Then** recent captures appear as thumbnails, newest first.
2. **Given** a capture with annotations, **When** the user reopens it from the library, **Then** every annotation is still selectable and editable.
3. **Given** a capture in the library, **When** the user deletes it, **Then** it is removed from the library after confirmation.

---

### User Story 5 - Refine the Image (Priority: P3)

The user crops the image, resizes it, and applies simple polish such as a border, drop shadow, or a slight rounded corner, so that screenshots look consistent in documents.

**Why this priority**: These are quality-of-life additions that are useful but not essential to the core capture and annotate loop.

**Independent Test**: Open an image, crop it, resize it, add a border and shadow, and export it.

**Acceptance Scenarios**:

1. **Given** an image in the editor, **When** the user crops it, **Then** the canvas shrinks to the selection and existing annotations that fall outside it are discarded or clipped.
2. **Given** an image in the editor, **When** the user applies a border or drop shadow, **Then** it appears in the preview and in the exported file.

---

### Edge Cases

- The user captures a region that spans multiple displays with different resolutions or scale factors.
- The user captures on a display with a very high resolution, producing a large image.
- A capture is requested while a protected window (for example, DRM video or a secure input field) is on screen. The protected content appears blank in the capture, and the user is not misled about this.
- The user changes screen capture permission while the app is running.
- The chosen save location is unavailable or the disk is full.
- The user quits with unsaved annotation changes.
- The capture shortcut conflicts with another app's or the system's shortcut.
- A very long text annotation, or many hundreds of annotations, is placed on one image.
- The system appearance switches between light and dark mode while the editor is open.

## Requirements *(mandatory)*

### Functional Requirements

**Capture**

- **FR-001**: Users MUST be able to start a capture from a configurable global keyboard shortcut and from a menu bar item.
- **FR-002**: Users MUST be able to capture a user-defined rectangular region, a single window, or a full display.
- **FR-003**: The system MUST capture at the display's native pixel resolution, including on Retina displays.
- **FR-004**: Users MUST be able to cancel a capture in progress without side effects.
- **FR-005**: The system MUST detect when screen capture permission is missing and guide the user to grant it.
- **FR-006**: Users MUST be able to choose whether the mouse cursor is included in a capture.
- **FR-007**: Users MUST be able to choose what happens after a capture (open in editor, copy to clipboard, save to a default folder), and these choices are remembered.

**Annotation**

- **FR-008**: The editor MUST provide these annotation tools: arrow, line, rectangle, ellipse, freehand pen, highlighter, text, and numbered step marker.
- **FR-009**: The editor MUST provide blur and pixelate tools for obscuring parts of an image.
- **FR-010**: Users MUST be able to set color, stroke thickness, and, for text, font and size, for each annotation.
- **FR-011**: Every annotation MUST remain independently selectable, movable, resizable, restylable, and deletable until the image is exported.
- **FR-012**: The editor MUST support unlimited undo and redo of all edits during an editing session.
- **FR-013**: Obscured regions MUST be irreversibly altered in exported output.
- **FR-014**: Users MUST be able to change the stacking order of overlapping annotations.
- **FR-015**: The editor MUST support zooming and panning the canvas.

**Output**

- **FR-016**: Users MUST be able to copy the flattened, annotated image to the clipboard.
- **FR-017**: Users MUST be able to save the annotated image as PNG or JPEG.
- **FR-018**: Users MUST be able to drag the annotated image out of the editor into other apps.
- **FR-019**: The editor MUST offer the standard macOS sharing options.

**Library and persistence**

- **FR-020**: The system MUST keep a library of recent captures with their editable annotations.
- **FR-021**: Users MUST be able to reopen, re-edit, and delete captures from the library.
- **FR-022**: The system MUST warn the user before discarding unsaved changes.

**Refinement**

- **FR-023**: Users MUST be able to crop and resize the image.
- **FR-024**: Users MUST be able to add a border and drop shadow to the image.

**General**

- **FR-025**: The app MUST support both light and dark appearance.
- **FR-026**: Captures and annotations MUST remain on the user's machine unless the user explicitly shares or exports them.

### Key Entities

- **Capture**: A screenshot image taken at a point in time. It has pixel dimensions, a capture time, and a source (region, window, or display).
- **Annotation**: A single mark placed on a capture. It has a type (for example arrow, text, blur), geometry, style (color, thickness, font), and stacking order. It belongs to exactly one capture.
- **Library**: The collection of a user's saved captures, with their annotations, ordered by capture time.
- **Preferences**: The user's settings, including capture shortcut, post-capture behavior, default save location and format, cursor inclusion, and default annotation styles.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can go from pressing the capture shortcut to having an image on the clipboard in under 5 seconds for a region capture.
- **SC-002**: A first-time user can capture a region, add an arrow and a text label, and copy the result in under 2 minutes without reading documentation.
- **SC-003**: The capture overlay appears within 300 milliseconds of the shortcut press, and the captured image opens in the editor within 1 second on a typical modern Mac.
- **SC-004**: Annotation interactions (drawing, moving, resizing) feel immediate, with no visible lag on images up to 5K resolution holding 100 annotations.
- **SC-005**: 100% of exported images with blur or pixelate applied have no recoverable original content in the obscured regions.
- **SC-006**: An image exported at a given zoom level matches the on-screen composition exactly, with annotations in the same positions and styles.
- **SC-007**: 100% of saved library captures reopen with all annotations still individually editable after the app is quit and relaunched.
- **SC-008**: In user testing, at least 90% of participants complete the primary task (capture, annotate, share) on their first attempt.

## Assumptions

- The app targets macOS only and is built natively as a Swift application in an Xcode project, as stated in the request. This is a given constraint, and detailed technical choices are left for the planning phase.
- Screen recording, video capture, and GIF creation are explicitly out of scope.
- Scrolling (long page) capture, panoramic capture, and OCR text extraction are out of scope for this release.
- Cloud sync, accounts, and any network-dependent features are out of scope. All data stays local.
- The app is for a single user on a single Mac and does not need to support collaboration.
- The user will grant the macOS screen capture permission when prompted. The app cannot capture without it.
- The minimum supported macOS version will be decided during planning, targeting reasonably current releases.
- PNG and JPEG are sufficient export formats for this release.
- Distribution method (Mac App Store, notarized direct download, or both) is not decided here and does not affect the requirements above.
