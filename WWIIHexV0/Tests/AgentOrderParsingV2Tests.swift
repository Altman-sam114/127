import XCTest
@testable import WWIIHexV0

final class AgentOrderParsingV2Tests: XCTestCase {
    func testSchemaV2DecodesRegionMoveOrder() throws {
        let json = """
        {
          "schemaVersion": 2,
          "agentId": "guderian",
          "turn": 1,
          "intent": "Advance",
          "orders": [
            {
              "type": "move",
              "divisionId": "ger_panzer_1",
              "toRegionId": "bastogne",
              "targetDivisionId": null,
              "stance": null,
              "reason": "Move to Bastogne."
            }
          ]
        }
        """

        let envelope = try AgentDecisionParser().parse(json, expectedAgentId: "guderian", expectedTurn: 1)

        XCTAssertEqual(envelope.schemaVersion, 2)
        XCTAssertEqual(envelope.orders.first?.toRegionId, "bastogne")
        XCTAssertNil(envelope.orders.first?.to)
    }

    func testSchemaV2MoveRequiresToRegionId() {
        let json = """
        {"schemaVersion":2,"agentId":"guderian","turn":1,"intent":"x","orders":[{"type":"move","divisionId":"ger_panzer_1","reason":"x"}]}
        """

        XCTAssertThrowsError(try AgentDecisionParser().parse(json, expectedAgentId: "guderian", expectedTurn: 1)) { error in
            XCTAssertEqual(error as? AgentDecisionParserError, .missingRegionDestination(divisionId: "ger_panzer_1"))
        }
    }

    func testLegacySchemaV1StillDecodesHexMoveOrder() throws {
        let json = """
        {
          "schemaVersion": 1,
          "agentId": "guderian",
          "turn": 1,
          "intent": "Advance",
          "orders": [
            {
              "type": "move",
              "divisionId": "ger_panzer_1",
              "to": { "q": 8, "r": 3 },
              "targetDivisionId": null,
              "stance": null,
              "reason": "Move west."
            }
          ]
        }
        """

        let envelope = try AgentDecisionParser().parse(json, expectedAgentId: "guderian", expectedTurn: 1)

        XCTAssertEqual(envelope.schemaVersion, 1)
        XCTAssertEqual(envelope.orders.first?.to, HexCoord(q: 8, r: 3))
        XCTAssertNil(envelope.orders.first?.toRegionId)
    }
}

