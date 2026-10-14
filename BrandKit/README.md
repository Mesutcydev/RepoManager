# Repo Manager brand kit

The approved mark is a sculpted repository case: three ivory file cards, a graphite housing, and one emerald inset. It was selected on 11 October 2026. The branch mark is retired. Git branch symbols remain only where they describe actual Git operations.

## Assets

- `Assets/repo-manager-app-icon.png`: full square master, 1254 × 1254. The production asset catalog uses a 1024 × 1024 opaque derivative; iOS supplies the corner mask.
- `Assets/repo-manager-mark-transparent.png`: 1280 × 1280 RGBA brand mark for onboarding, navigation, and the splash animation.
- `colors.json`: exact sRGB semantic colors, including light and dark appearance values.
- `../Docs/Design/REPOSITORY_CASE_PROMPT.txt`: generation prompt for the approved master. Built-in image generation was used. Reference screenshots guided materials and rendering; their original artwork is not distributed.

Keep the full silhouette, ceramic layers, graphite rim, and emerald inset together. Keep clear space equal to one quarter of the visible case height. Use the transparent mark at 44pt or larger; use the opaque icon for the home screen. Do not recolor the ceramic, add a glow, stretch the case, place code brackets over it, or bring back a branch emblem.

## Color

| Role | Dark | Light |
| --- | --- | --- |
| Canvas | `#111315` | `#F5F2EB` |
| Raised surface | `#1C2023` | `#FFFEFA` |
| Composer | `#24282B` | `#E8E5DE` |
| Primary text | `#F5F2EB` | `#17201C` |
| Secondary text | `#B4BDB7` | `#55645C` |
| Action | `#67D4A1` | `#087A51` |
| Accent text | `#7BE6B1` | `#076743` |
| Dividers | `#3B4144` | `#C7CFC8` |
| Destructive state | `#FF716F` | `#B32632` |

Dark is the initial appearance. The app preserves a user's explicit System, Light, Dark, or OLED choice. Emerald identifies active scope, ready states, and primary actions. Destructive actions and Stop use red. Color always accompanies a label or symbol.

## Typography

Native San Francisco supplies optical sizing and Dynamic Type. Do not bundle Apple font binaries.

| Use | SwiftUI font | Detail |
| --- | --- | --- |
| Wordmark | `.title3`, default, semibold | Tracking −0.45pt |
| Page title | `.largeTitle`, serif | Tracking −0.7pt; natural wrapping |
| Object or profile title | `.title2`, medium | Sentence case |
| Navigation | `.body` | Medium for selected destinations |
| Body | `.body` or `.subheadline` | Natural line breaks; 3–4pt added line spacing in descriptive copy |
| Metadata | `.caption`, monospaced | Repository, branch, model protocol, and timestamps |
| Section eyebrow | `.caption2`, monospaced, medium | Uppercase, 1.5pt tracking |
| Code | `.body` or `.footnote`, monospaced | Selectable; semantic size |

Use short concrete titles. Avoid promotional slogans, gradients behind every panel, icon tiles for every setting, and ornamental menu cards. Settings and review forms use native controls; the sidebar, history, provider chooser, and landing screens use deliberate typography and spacing.

## Geometry and motion

Use a 4pt spacing grid, 24–28pt page margins, 44pt minimum hit targets, and 52pt primary buttons. Readable pages center at 600–800pt. Chat retains its original composer geometry and leading keyboard-dismiss key.

The OS launch screen is a static graphite canvas. Once the app owns its view, the case enters from 97% scale and an 8pt offset over 220ms, its cards settle with a restrained 380ms spring, the inset brightens once, and the wordmark enters over 180ms. The case settles over 800ms, followed by a 120ms fade through the matching canvas and a 180ms page entrance. Total minimum handoff is approximately 1.13 seconds. It runs once per cold process launch, waits for encrypted storage restoration, and never repeats on navigation or foregrounding. No audio, network calls, haptic feedback, looping shimmer, or fake progress is attached to the animation.

Reduce Motion removes translation, scaling, and the inset highlight. A short opacity entrance preserves continuity. Typing, keyboard shortcuts, chat switching, and ordinary tool results remain immediate. The drawer tracks the finger and uses an interruptible 300ms spring.

## Implementation

The application consumes the kit through `RMBrand`, `RMBrandGlyph`, `RMWordmark`, `RMSplashScreen`, and semantic asset-catalog colors. Onboarding, the drawer and app icon use the same approved case. The app-switcher privacy cover was removed in build 9. The splash layers sample one master image; the settled frame displays the untouched master, avoiding mask seams.

The app and Share extension have independent Repo Manager identifiers. No reference-project asset catalog or dependency was changed.
