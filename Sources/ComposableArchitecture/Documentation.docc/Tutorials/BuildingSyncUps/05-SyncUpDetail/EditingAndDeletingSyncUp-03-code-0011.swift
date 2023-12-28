import ComposableArchitecture

@Reducer
struct SyncUpDetail {
  @ObservableState
  struct State {
    @Presents var destination: Destination.State?
    var syncUp: SyncUp
  }

  enum Action {
    case cancelEditButtonTapped
    case delegate(Delegate)
    case deleteButtonTapped
    case destination(PresentationAction<Destination.Action>)
    case doneEditingButtonTapped
    case editButtonTapped
    case startMeetingButtonTapped
    case meetingTapped(id: Meeting.ID)
    enum Alert {
      case confirmButtonTapped
    }
    enum Delegate {
      case deleteSyncUp(id: SyncUp.ID)
    }
  }

  @Dependency(\.dismiss) var dismiss

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      // case .alert(.presented(.confirmButtonTapped)):
      case .destination(.presented(.alert(.confirmButtonTapped))):
        return .run { send in
          await send(.delegate(.deleteSyncUp(id: state.syncUp.id)))
          await dismiss()
        }

      case .destination(.dismiss):
        return .none

      case .cancelEditButtonTapped:
        state.destination = nil
        return .none

      case .delegate:
        return .none

      case .deleteButtonTapped:
        return .none

      case .doneEditingButtonTapped:
        guard let editedSyncUp = state.editSyncUp?.syncUp
        else { return .none }
        state.syncUp = editedSyncUp
        return .none

      case .editButtonTapped:
        state.editSyncUp = SyncUpForm.State(syncUp: state.syncUp)
        return .none

      case .startMeetingButtonTapped:
        return .none

      case let .meetingTapped(id: id):
        return .none
      }
    }
    .ifLet(\.$destination, action: \.destination) {
      Destination()
    }
  }
}

struct SyncUpDetail.Destination {
  // ...
}

struct SyncUpDetailView {
  // ...
}
