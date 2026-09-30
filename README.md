# MnM on Mac

![MnM on Mac](https://raw.githubusercontent.com/seathasky/MnM-on-Mac/refs/heads/main/Preview.png)

MnM on Mac is an independent community app for playing [Monsters & Memories](https://monstersandmemories.com/) on macOS.

The app sets up a self-contained Wine environment...no CrossOver installation required. Version 2.0 uses the official launcher for signing in, installing, updating, repairing, and playing, with Mac controls attached beneath its window.

> **Beta:** Report problems through [GitHub Issues](https://github.com/seathasky/MnM-on-Mac/issues) or [Seathasky Dev Discord](https://discord.gg/9w6ZdaksDX).

## Features

- Apple silicon support and guided setup
- D3DMetal, DXMT, and DXVK graphics options
- MetalFX Upscaling with DXMT
- macOS Game Mode controls, where supported
- Automatic screen-fit sizing with live launcher scaling
- Game Folder, Discord, About, and Legal buttons
- Built-in app update checks

## Installation

1. Download the latest build from [Releases](https://github.com/seathasky/MnM-on-Mac/releases).
2. Move **MnM on Mac.app** to Applications and open it.
3. Follow setup prompts, including Rosetta installation if required.
4. Sign in, install, and play through the official launcher.

**First-time setup can take 5–15 minutes, depending on your Mac and internet speed.** Downloading the game may take additional time.

## Controls & Updates

Use the attached footer for graphics selection and game-folder access. The cogwheel includes launcher scaling and performance settings.

The official launcher handles the game. MnM on Mac checks for app updates separately.

## Troubleshooting

- **Window too large:** Cogwheel → Launcher Scale → Automatic (Fit Screen).
- **Loading screen stuck:** Quit MnM on Mac completely and reopen it.
- **Sign-in problems:** Tools → Re-authenticate…
- **Missing game files:** Tools → Choose Game Folder… and select the folder containing `mnm.exe`.

Application support files and logs are stored in:

    ~/Library/Application Support/MnM on Mac

Use **Game Folder** to locate the game installation.

## Credits

Monsters & Memories and its artwork belong to the official development team. MnM on Mac is not affiliated with or endorsed by them.

Built with work from WineHQ, Sikarugir, DXMT, and wine-msync contributors. Full acknowledgements and licenses are available inside the app.

## License

Source code is available under the [MIT License](LICENSE). Third-party components retain their respective licenses.
