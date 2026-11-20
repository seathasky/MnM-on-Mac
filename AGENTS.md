# Regression tests

After each change, run `bash LauncherCompatibility/run_regressions.sh` on macOS. Report any failures and which behavior remains unverified. The suite uses temporary fixtures and does not launch or install MnM on Mac.

Changes to the updater, Wine runtime, or prefix migration also need an isolated signed upgrade test before release. Run the previous release and the candidate against disposable copies and check that the updater finishes, the candidate opens, and player data survives.
