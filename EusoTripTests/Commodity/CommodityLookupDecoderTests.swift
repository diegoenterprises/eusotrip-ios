import XCTest
@testable import EusoTrip

final class CommodityLookupDecoderTests: XCTestCase {
    func testChemicalResultUsesProductNameAndUNNumber() throws {
        let response = try decode("""
        {
          "results": [{
            "productName": "Sulphuric acid",
            "pollutionCategory": "C",
            "shipType": 3,
            "tankType": "Type 2",
            "unNumber": "1830",
            "hazards": "Corrosive"
          }],
          "count": 1,
          "source": "database"
        }
        """)

        XCTAssertEqual(response.results.first?.name, "Sulphuric acid")
        XCTAssertEqual(response.results.first?.code, "1830")
        XCTAssertEqual(response.results.first?.category, "Pollution C · ship type 3")
        XCTAssertEqual(response.results.first?.note, "Corrosive")
        XCTAssertEqual(response.source, "database")
    }

    func testPetroleumResultUsesProductIdentity() throws {
        let response = try decode("""
        {
          "results": [{
            "product": "West Texas Intermediate (WTI) crude",
            "apiGravityBand": "38-40 (light sweet)",
            "apiGravity": 39.6,
            "sulfurClass": "Sweet",
            "sulfurContent": 2400,
            "rvp": 9,
            "flashPoint": -20,
            "vaporRecovery": true,
            "defaultHose": "4in Crude (camlock)"
          }],
          "count": 1,
          "source": "database"
        }
        """)

        XCTAssertEqual(response.results.first?.name, "West Texas Intermediate (WTI) crude")
        XCTAssertEqual(response.results.first?.category, "Sweet")
        XCTAssertEqual(response.results.first?.note, "4in Crude (camlock)")
    }

    func testReeferResultUsesProductNameAndTemperatureBand() throws {
        let response = try decode("""
        {
          "results": [{
            "productName": "Fresh Produce (mixed)",
            "tempMinF": 32,
            "tempMaxF": 40,
            "toleranceF": 3,
            "monitoringIntervalMin": 30,
            "fsmaRegulated": true,
            "ethyleneSensitive": true,
            "notes": "Separate ethylene producers"
          }],
          "count": 1,
          "source": "database",
          "best": null
        }
        """)

        XCTAssertEqual(response.results.first?.name, "Fresh Produce (mixed)")
        XCTAssertEqual(response.results.first?.tempLowF, 32)
        XCTAssertEqual(response.results.first?.tempHighF, 40)
        XCTAssertEqual(response.results.first?.preCool, nil)
        XCTAssertEqual(response.results.first?.category, "FSMA-regulated")
    }

    func testContainerResultUsesISOCodeAndName() throws {
        let response = try decode("""
        {
          "results": [{
            "isoCode": "45R1",
            "name": "40ft Reefer High-Cube (40RF)",
            "lengthFt": 37.917,
            "widthFt": 7.417,
            "heightFt": 7.5,
            "payloadKg": 23904,
            "tareKg": 4400,
            "cubicCapacityM3": 59.6,
            "class": "reefer"
          }],
          "count": 1,
          "source": "database"
        }
        """)

        XCTAssertEqual(response.results.first?.name, "40ft Reefer High-Cube (40RF)")
        XCTAssertEqual(response.results.first?.code, "45R1")
        XCTAssertEqual(response.results.first?.category, "reefer")
    }

    func testSTCCResultUsesDescriptionWithoutRequiringName() throws {
        let response = try decode("""
        {
          "results": [{
            "stcc": "2911160",
            "description": "Crude petroleum (UN1267)",
            "hazmatLinked": true
          }],
          "count": 1,
          "source": "database"
        }
        """)

        XCTAssertEqual(response.results.first?.name, "Crude petroleum (UN1267)")
        XCTAssertEqual(response.results.first?.code, "2911160")
        XCTAssertEqual(response.results.first?.category, "STCC · hazmat-linked")
    }

    private func decode(_ json: String) throws -> CommodityLookupAPI.SearchResponse {
        try JSONDecoder().decode(
            CommodityLookupAPI.SearchResponse.self,
            from: Data(json.utf8)
        )
    }
}
