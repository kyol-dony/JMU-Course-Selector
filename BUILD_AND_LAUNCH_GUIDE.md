# Build and Launch Guide

## Build and open the app

Building from source requires Apple's Swift/Xcode command line tools. Use the included helper:

1. Double-click `Build App.command`.
2. Wait for the window to say the app was built.
3. Open `dist/JMU Course Planner.app`.

The generated `dist` folder is ignored by Git. Ready-built apps are attached to each GitHub Release as a `.zip`. Local builds and direct-download releases are not notarized.

For ready-built downloads, follow [the installation guide](docs/INSTALLATION.txt). Each new release includes it inside the app ZIP and as a separate **START HERE** download.

If macOS blocks the app because it cannot verify the developer:

1. Try opening the app once, then dismiss the warning.
2. Open **System Settings → Privacy & Security**.
3. Scroll to **Security** and select **Open Anyway** for JMU Course Planner.
4. Confirm **Open** when macOS asks again.

This is a per-app exception. Do not disable Gatekeeper or change global security settings. A school-managed Mac may prevent **Open Anyway**; contact its administrator when that happens.

## Run tests

1. Double-click `Run Tests.command`.
2. Wait for the test window to finish.
3. A successful run says the test suites passed.

The tests cover schedule generation, prerequisite warnings and overrides, AP transfer credit mapping, and graduation progress calculations.

## Save files

Plans are saved locally in your Mac user Application Support folder as readable `.jmuplan.json` files. The app also keeps an autosave so a network failure does not erase in-progress work.
