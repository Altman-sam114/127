import XCTest
@testable import WWIIHexV0

final class CommandValidationRegionTests: XCTestCase {
    func testRegionMoveValidationRejectsMissingRegion() {
        let state = RegionRuleTestFixtures.state(
            divisions: [
                RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 1, r: 0))
            ]
        )
        let command = RegionCommand.move(divisionId: "allied", from: "forest_road", to: "missing")

        XCTAssertEqual(RegionCommandValidator().validate(command, in: state).errors, [.regionNotFound])
    }

    func testRegionMoveValidationRejectsWrongFromRegion() {
        let state = RegionRuleTestFixtures.state(
            divisions: [
                RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 1, r: 0))
            ]
        )
        let command = RegionCommand.move(divisionId: "allied", from: "bastogne", to: "st_vith")

        XCTAssertEqual(RegionCommandValidator().validate(command, in: state).errors, [.invalidRegionForHex])
    }

    func testRegionAttackValidationRejectsSameFactionTarget() {
        let state = RegionRuleTestFixtures.state(
            divisions: [
                RegionRuleTestFixtures.division(id: "a1", faction: .allies, coord: HexCoord(q: 1, r: 0)),
                RegionRuleTestFixtures.division(id: "a2", faction: .allies, coord: HexCoord(q: 2, r: 0))
            ]
        )
        let command = RegionCommand.attack(
            attackerId: "a1",
            from: "forest_road",
            targetDivisionId: "a2",
            targetRegionId: "bastogne"
        )

        XCTAssertEqual(RegionCommandValidator().validate(command, in: state).errors, [.invalidTargetFaction])
    }

    func testPlayerAndAIShareHexValidatorAfterMapping() throws {
        let state = RegionRuleTestFixtures.state(
            divisions: [
                RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 1, r: 0))
            ]
        )
        let order = AgentOrder(
            type: .move,
            divisionId: "allied",
            toRegionId: "bastogne",
            reason: "Advance."
        )
        let issued = try AgentCommandMapper().map(order, agentId: "test_agent", state: state)

        XCTAssertEqual(CommandValidator().validate(issued.command, in: state), .valid)
    }
}

