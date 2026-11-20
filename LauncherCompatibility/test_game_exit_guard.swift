@main struct GameExitGuardTest {
    static func main() {
        let playing = GameExitGuard(gameIsRunning: true)
        let idle = GameExitGuard(gameIsRunning: false)
        assert(!playing.canExitAutomatically)
        assert(idle.canExitAutomatically)
        assert(idle.canExit { fatalError("must not prompt") })
        assert(!playing.canExit { false })
        assert(playing.canExit { true })
        print("Game exit guard tests passed.")
    }
}
