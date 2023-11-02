import ComposableArchitecture
import SwiftUI

@Reducer
struct Todo {
  @ObservableState
  struct State: Equatable, Identifiable {
    var description = ""
    let id: UUID
    var isComplete = false
  }

  enum Action: BindableAction, Equatable, Sendable {
    case binding(BindingAction<State>)
  }

  var body: some Reducer<State, Action> {
    BindingReducer()
  }
}

struct TodoView: View {
  @State var store: StoreOf<Todo>

  var body: some View {
    HStack {
      Button {
        store.isComplete.toggle()
      } label: {
        Image(systemName: store.isComplete ? "checkmark.square" : "square")
      }
      .buttonStyle(.plain)

      TextField("Untitled Todo", text: $store.description)
    }
    .foregroundColor(store.isComplete ? .gray : nil)
  }
}
