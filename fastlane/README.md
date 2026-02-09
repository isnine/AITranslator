fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Capture screenshots on all configured devices and languages

### ios frames

```sh
[bundle exec] fastlane ios frames
```

Add device frames and marketing text to screenshots

### ios deliver_screenshots

```sh
[bundle exec] fastlane ios deliver_screenshots
```

Capture screenshots, frame them, and upload to App Store Connect

### ios upload_only

```sh
[bundle exec] fastlane ios upload_only
```

Upload existing framed screenshots to App Store Connect

### ios full_pipeline

```sh
[bundle exec] fastlane ios full_pipeline
```

Full screenshot pipeline: capture, frame, and upload

### ios download_metadata

```sh
[bundle exec] fastlane ios download_metadata
```

Download metadata from App Store Connect to local metadata/ directory

Usage: fastlane deliver download_metadata --api_key_path ./fastlane/api_key.json

Note: api_key.json must contain key_id, issuer_id, key (inline p8 content), in_house fields

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload all metadata (description, keywords, what's new, etc.) to App Store Connect

### ios release

```sh
[bundle exec] fastlane ios release
```

Full release: upload metadata + screenshots

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
