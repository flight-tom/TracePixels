# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

SnagItForever is a native macOS clone of SnagIt (screen capture and annotation). See `README.md`.

## Current state

The repository is a fresh scaffold: it contains only `README.md`, `LICENSE`, `.gitattributes`, and an Xcode/Swift-oriented `.gitignore`. There is no source code, Xcode project, or Swift package yet, so there are no build, lint, or test commands to document.

The `.gitignore` (Xcode / Swift Package Manager / CocoaPods-style) implies a Swift-based Xcode project, but the app structure, minimum macOS version, and UI framework (AppKit vs. SwiftUI) have not been decided in the repo.

## Updating this file

Once the Xcode project or Swift package is added, re-run `/init` or update this file with:
- build, run, and test commands (including how to run a single test)
- the high-level architecture (capture pipeline, annotation/editor model, export, etc.)
- required macOS permissions (e.g. Screen Recording) and how they are handled during development
