# MnM on Mac

![MnM on Mac](https://i.imgur.com/yWviL69.png)

MnM on Mac is an independent community launcher for installing, updating, and playing [Monsters & Memories](https://monstersandmemories.com/) on macOS.

The app prepares a self-contained Windows environment using Wine, so no separate CrossOver installation is required. The official Monsters & Memories launcher handles signing in, installation, and updates. After setup, MnM on Mac can launch the game directly.

> **Beta:** MnM on Mac is still being tested. Back up anything important and report problems through GitHub Issues.

## Features

- Native macOS interface with Apple silicon support
- Guided Wine and game setup
- Direct game launching after the initial installation
- Access to the official launcher for login, updates, and repairs
- Custom game-folder selection
- Graphics Engine selection including D3DMetal, DXMT and DXVK.
- Option to enable MacOS Game Mode.
- Developer ID signed and notarized by Apple

## Installation

1. Download the latest build from [Releases](https://github.com/seathasky/MnM-on-Mac/releases).
2. Move **MnM on Mac.app** to your Applications folder.
3. Open the app and select **Set Up Wine**.
4. Sign in and install the game through the official launcher when prompted.
5. Return to MnM on Mac and use **Play** for normal launches.

The first setup downloads Wine and its support files, so it may take several minutes.

## Updating the Game

Select **Install /Update / Login** to open the official Monsters & Memories launcher. Let it finish updating, close it, and return to MnM on Mac.

## Troubleshooting

### Re-authenticate

If the game asks you to re-authenticate, select **Re-authenticate…** in MnM on Mac. This resets and backs up the official launcher's saved login session without deleting the installed game. Sign in again through the official launcher afterward.

### Game Files Not Found

Select **Choose Game Folder…** and choose the folder that directly contains `mnm.exe`.

Application data is stored in:

```text
~/Library/Application Support/MnM on Mac
```

## Credits

Monsters & Memories and its artwork are created by the official Monsters & Memories development team. Visit the [official website](https://monstersandmemories.com/) to learn more.

MnM on Mac uses open-source work from the WineHQ, Sikarugir, DXMT, and wine-msync contributors. Full acknowledgements and licenses are available inside the app.

MnM on Mac is an independent community project and is not affiliated with or endorsed by the Monsters & Memories team.

## License

MnM on Mac source code is available under the [MIT License](LICENSE). Third-party components remain subject to their respective licenses.
