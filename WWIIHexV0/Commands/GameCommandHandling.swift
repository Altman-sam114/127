import Foundation

protocol GameCommandHandling {
    func execute(_ command: Command, in state: GameState) -> CommandResult
}

extension RuleEngine: GameCommandHandling {}
