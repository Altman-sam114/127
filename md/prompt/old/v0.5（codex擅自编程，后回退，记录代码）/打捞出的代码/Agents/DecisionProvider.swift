import Foundation

protocol DecisionProvider {
    func commands(for state: GameState) async throws -> [Command]
}
