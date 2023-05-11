import ComposableArchitecture
import XCTest

@testable import SwiftUICaseStudies

@MainActor
final class RecursionTests: XCTestCase {
  func testAddRow() async {
    let store = TestStore(
      initialState: Nested.State(id: UUID()),
      reducer: Nested()
    ) {
      $0.uuid = .incrementing
    }

    let id0 = UUID(0)
    let id1 = UUID(1)

    await store.send(.addRowButtonTapped) {
      $0.rows.append(Nested.State(id: id0))
    }

    await store.send(.row(id: id0, action: .addRowButtonTapped)) {
      $0.rows[id: id0]?.rows.append(Nested.State(id: id1))
    }
  }

  func testChangeName() async {
    let store = TestStore(
      initialState: Nested.State(id: UUID()),
      reducer: Nested()
    )

    await store.send(.nameTextFieldChanged("Blob")) {
      $0.name = "Blob"
    }
  }

  func testDeleteRow() async {
    let id0 = UUID(0)
    let id1 = UUID(1)
    let id2 = UUID(2)

    let store = TestStore(
      initialState: Nested.State(
        id: UUID(),
        rows: [
          Nested.State(id: id0),
          Nested.State(id: id1),
          Nested.State(id: id2),
        ]
      ),
      reducer: Nested()
    )

    await store.send(.onDelete(IndexSet(integer: 1))) {
      $0.rows.remove(id: id1)
    }
  }
}
