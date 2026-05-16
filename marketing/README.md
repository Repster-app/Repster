# Repster Launch Marketing Kit

This folder implements the lean launch marketing plan for Repster.

Core message:

> A fast lifting log that keeps your training history useful while you train.

Primary audience:

Consistent lifters who already track workouts and want faster logging, useful history, PRs, templates, charts, and local-first control.

## Folder Map

- `app-store/product-page.md`: App Store metadata, screenshot order, preview storyboard, and capture requirements.
- `generated/app-store/`: Six 1320 x 2868 PNG screenshot frames for App Store Connect.
- `generated/social/static/`: Six 1080 x 1350 static launch posts.
- `generated/social/video-covers/`: Twelve 1080 x 1920 cover frames for short-form posts.
- `social/social-launch-kit.md`: Short-form video scripts, static post copy, and publishing notes.
- `press/creator-press-kit.md`: One-paragraph description, creator DM, email pitch, and press kit checklist.
- `website/`: Static marketing website refresh that uses the same screenshot frame language.
- `metrics/launch-measurement.md`: Launch tracking plan and iteration cadence.
- `source/`: Source logo and screenshots used by the renderer.
- `tools/render_marketing_assets.swift`: Reproducible local renderer for the generated PNG assets.

## Regenerate Assets

Run this from the repository root:

```sh
mkdir -p .build/module-cache
CLANG_MODULE_CACHE_PATH=.build/module-cache swift marketing/tools/render_marketing_assets.swift
```

The module cache path keeps Swift compiler output inside the workspace.

## Current Asset Status

Ready now:

- App Store screenshot frames 1-5 use real app screenshots for active logging, templates, history, PR/home, and charts.
- Social static posts and video cover frames are generated from the same real UI sources.
- Website refresh, app preview storyboard, launch copy, creator pitch, and tracking plan are ready.

Needs final capture before App Store submission:

- `generated/app-store/06-import-history-and-keep-control.png` is a draft frame. Replace its source with a final import, export, or backup settings screenshot before submission.
- The 20-30 second App Store preview still needs real device-captured screen recording. The storyboard is in `app-store/product-page.md`.
- The 12 short-form posts are scripted and cover-framed; record or edit the actual 9:16 videos from the storyboard in `social/social-launch-kit.md`.

