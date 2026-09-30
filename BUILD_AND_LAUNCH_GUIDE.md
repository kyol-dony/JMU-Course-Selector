# Build and Launch Guide

## Build and open the app

Building from source requires Apple's Swift/Xcode command line tools. Use the included helper:

1. Double-click `Build App.command`.
2. Wait for the window to say the app was built.
3. Open `dist/JMU Course Planner.app`.

The generated `dist` folder is ignored by Git. Release app bundles will be distributed separately. If macOS says a local build is from an unidentified developer, right-click the app, choose **Open**, then choose **Open** again. Local builds are not notarized.

## Run tests

1. Double-click `Run Tests.command`.
2. Wait for the test window to finish.
3. A successful run says the test suites passed.

The tests cover schedule generation, prerequisite warnings and overrides, AP transfer credit mapping, and graduation progress calculations.

## Save files

Plans are saved locally in your Mac user Application Support folder as readable `.jmuplan.json` files. The app also keeps an autosave so a network failure does not erase in-progress work.
