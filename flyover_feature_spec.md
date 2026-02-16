# Flyover Activity Video Generator

Strava → GPX → Mapbox → MP4

------------------------------------------------------------------------

## 1. Product Overview

This app generates cinematic flyover videos from running or cycling
activities.

It supports:

-   GPX file import
-   Direct activity import from Strava
-   Route animation using Mapbox
-   Automatic MP4 video export
-   Social media--ready format (9:16 & 16:9)

------------------------------------------------------------------------

# 2. Core Feature List (MVP)

------------------------------------------------------------------------

## 2.1 GPX Import Module

### Functional Requirements

-   Accept `.gpx` file via:
    -   File picker
    -   Android share intent
    -   iOS share extension
-   Parse GPX file
-   Extract:
    -   Latitude
    -   Longitude
    -   Elevation (optional)
    -   Timestamp (optional)
-   Convert to internal route model

### Output Model

``` dart
class RoutePoint {
  final double lat;
  final double lng;
  final double? elevation;
  final DateTime? timestamp;
}
```

------------------------------------------------------------------------

## 2.2 Strava OAuth Integration

### Functional Requirements

-   OAuth login flow
-   Store access token securely
-   Fetch user activities
-   Fetch activity streams:
    -   latlng
    -   time
    -   altitude (optional)

### API Endpoint

GET /activities/{id}/streams?keys=latlng,time,altitude

Convert API response into internal `RoutePoint` list.

------------------------------------------------------------------------

## 2.3 Route Processing Engine

### Required Algorithms

1.  Route Simplification
    -   Implement Ramer-Douglas-Peucker algorithm\
    -   Reduce unnecessary GPS noise
2.  Bearing Calculation
    -   Calculate camera direction from point A → B
3.  Interpolation
    -   Generate evenly spaced points\
    -   Target fixed FPS (e.g., 30 fps)

------------------------------------------------------------------------

## 2.4 Map Rendering Engine

### Requirements

-   Initialize Mapbox map
-   Enable 3D terrain (optional in MVP)
-   Add polyline layer
-   Style route line (color, width, glow optional)

------------------------------------------------------------------------

## 2.5 Camera Animation Engine

### Behavior

For each interpolated route point:

-   Camera center = current point
-   Bearing = direction of movement
-   Pitch = 60°
-   Zoom = dynamic (14--17)
-   Smooth easing

### Controls

-   Animation speed multiplier
-   Pause / resume
-   Restart

------------------------------------------------------------------------

## 2.6 Frame Capture System

### Requirements

-   Capture map snapshot per frame
-   Save to temporary storage:

/frames/frame_0001.png

### Performance Constraints

-   Avoid memory overflow
-   Clear unused frames progressively

------------------------------------------------------------------------

## 2.7 Video Rendering (FFmpeg)

### Requirements

-   Convert frames to MP4
-   Target:
    -   30 FPS
    -   H.264 codec
-   Support:
    -   16:9
    -   9:16

Example command:

ffmpeg -framerate 30 -i frame\_%04d.png -c:v libx264 output.mp4

------------------------------------------------------------------------

## 2.8 Export & Share Module

### Requirements

-   Save video to gallery
-   Share to:
    -   Instagram
    -   TikTok
    -   WhatsApp
-   Generate preview thumbnail

------------------------------------------------------------------------

# 3. UI Feature Requirements

------------------------------------------------------------------------

## 3.1 Activity Selection Screen

-   List imported GPX files
-   List Strava activities
-   Show:
    -   Distance
    -   Duration
    -   Date

------------------------------------------------------------------------

## 3.2 Video Customization Screen

User can adjust:

-   Video ratio (16:9 / 9:16)
-   Map style (dark/light)
-   Route color
-   Animation speed
-   Show distance overlay (toggle)
-   Show pace overlay (optional)

------------------------------------------------------------------------

## 3.3 Rendering Progress Screen

-   Progress bar
-   Frame generation count
-   Estimated remaining time
-   Cancel button

------------------------------------------------------------------------

# 4. Non-Functional Requirements

------------------------------------------------------------------------

## Performance

-   Smooth animation at 30 FPS
-   No UI blocking during rendering
-   Background processing supported

------------------------------------------------------------------------

## Storage

-   Auto-delete frames after video export
-   Cache limit management

------------------------------------------------------------------------

## Security

-   Secure token storage
-   No plaintext Strava token

------------------------------------------------------------------------

# 5. Phase 2 Features (Advanced)

------------------------------------------------------------------------

## 5.1 3D Elevation Exaggeration

-   Enable terrain exaggeration
-   Dynamic camera height

------------------------------------------------------------------------

## 5.2 Speed-Based Animation

-   Faster movement when user pace is higher
-   Use timestamp stream

------------------------------------------------------------------------

## 5.3 Overlay System

Add dynamic overlays:

-   Distance counter
-   Moving dot
-   Elevation chart
-   Personal branding watermark

------------------------------------------------------------------------

## 5.4 Music Integration

-   Import audio file
-   Trim automatically to video duration
-   Mix with FFmpeg

------------------------------------------------------------------------

# 6. Suggested Folder Architecture

    lib/
     ├── core/
     │    ├── models/
     │    ├── algorithms/
     │    └── services/
     ├── features/
     │    ├── gpx_import/
     │    ├── strava_auth/
     │    ├── map_render/
     │    ├── animation_engine/
     │    ├── video_export/
     │    └── overlays/
     └── ui/
          ├── screens/
          ├── widgets/
          └── components/

------------------------------------------------------------------------

# 7. MVP Definition

Must Ship First:

-   GPX import\
-   Basic flyover animation\
-   Frame capture\
-   MP4 export

Exclude in MVP:

-   Overlays\
-   Music\
-   3D terrain

------------------------------------------------------------------------

# 8. Future Monetization Hooks

-   Watermark removal (Pro)
-   4K export (Pro)
-   Faster rendering (Pro)
-   Custom branding pack (Pro)
