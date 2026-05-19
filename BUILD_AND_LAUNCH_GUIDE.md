# Build and Launch Guide

## Open the app

1. Open this project folder in Finder.
2. Open the `dist` folder.
3. Double-click `JMU Course Planner.app`.

If macOS says the app is from an unidentified developer, right-click the app, choose **Open**, then choose **Open** again. This local build is not notarized.

## If the app has not been built yet

Use the included helper:

1. Double-click `Build App.command`.
2. Wait for the window to say the app was built.
3. Open `dist/JMU Course Planner.app`.

Building from source requires Apple’s Swift/Xcode command line tools. Running the already-built app does not.

## Run tests

1. Double-click `Run Tests.command`.
2. Wait for the test window to finish.
3. A successful run says the test suites passed.

The tests cover schedule generation, prerequisite warnings and overrides, AP transfer credit mapping, and graduation progress calculations.

## Save files

Plans are saved locally in your Mac user Application Support folder as readable `.jmuplan.json` files. The app also keeps an autosave so a network failure does not erase in-progress work.
