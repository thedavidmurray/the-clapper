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

### ios register_app

```sh
[bundle exec] fastlane ios register_app
```

Register com.edgeless.theclapper on App Store Connect (idempotent)

### ios certs

```sh
[bundle exec] fastlane ios certs
```

Fetch / create distribution provisioning profile

### ios archive_ipa

```sh
[bundle exec] fastlane ios archive_ipa
```

Build a signed app-store IPA (no upload)

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build + upload to TestFlight

### ios push_listing

```sh
[bundle exec] fastlane ios push_listing
```

Push metadata + screenshots to the App Store listing (no submit, no binary)

### ios verify_listing

```sh
[bundle exec] fastlane ios verify_listing
```

Verify the editable App Store version is ready to submit

### ios diagnose_submit

```sh
[bundle exec] fastlane ios diagnose_submit
```

Diagnose why the version is not in a submittable state

### ios release

```sh
[bundle exec] fastlane ios release
```

Submit current TestFlight build for App Store review

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
