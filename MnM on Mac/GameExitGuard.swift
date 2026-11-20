struct GameExitGuard {
    let gameIsRunning: Bool

    var canExitAutomatically: Bool { !gameIsRunning }

    func canExit(confirm: () -> Bool) -> Bool {
        canExitAutomatically || confirm()
    }
}
