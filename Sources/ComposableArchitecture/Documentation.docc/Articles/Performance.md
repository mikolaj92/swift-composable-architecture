# Performance

Learn how to improve the performance of features built in the Composable Architecture.

As your features and application grow you may run into performance problems, such as reducers
becoming slow to execute, SwiftUI view bodies executing more often than expected, and more. This
article outlines a few common pitfalls when developing features in the library, and how to fix
them.

* [View stores](#View-stores)
* [Sharing logic with actions](#Sharing-logic-with-actions)
* [CPU-intensive calculations](#CPU-intensive-calculations)
* [High-frequency actions](#High-frequency-actions)
* [Store scoping](#Store-scoping)
* [Compiler performance](#Compiler-performance)

### View stores

A common performance pitfall when using the library comes from constructing ``ViewStore``s, which
is the object that observes changes to your feature's state. When constructed naively, using either 
view store's initializer ``ViewStore/init(_:observe:)-3ak1y`` or the SwiftUI helper
``WithViewStore``, it  will observe every change to state in the store:

```swift
WithViewStore(self.store, observe: { $0 }) { viewStore in 
  // This is executed for every action sent into the system 
  // that causes self.store.state to change. 
}
```

Most of the time this observes far too much state. A typical feature in the Composable Architecture
holds onto not only the state the view needs to present UI, but also state that the feature only
needs internally, as well as state of child features embedded in the feature. Changes to the
internal and child state should not cause the view's body to re-compute since that state is not
needed in the view.

For example, if the root of our application was a tab view, then we could model that in state as a
struct that holds each tab's state as a property:

```swift
@Reducer
struct AppFeature {
  struct State {
    var activity: Activity.State
    var search: Search.State
    var profile: Profile.State
  }
  // ...
}
```

If the view only needs to construct the views for each tab, then no view store is even needed
because we can pass scoped stores to each child feature view:

```swift
struct AppView: View {
  let store: StoreOf<AppFeature>

  var body: some View {
    // No need to observe state changes because the view does
    // not need access to the state.

    TabView {
      ActivityView(
        store: self.store
          .scope(state: \.activity, action: \.activity)
      )
      SearchView(
        store: self.store
          .scope(state: \.search, action: \.search)
      )
      ProfileView(
        store: self.store
          .scope(state: \.profile, action: \.profile)
      )
    }
  }
}
```

This means `AppView` does not actually need to observe any state changes. This view will only be
created a single time, whereas if we observed the store then it would re-compute every time a single
thing changed in either the activity, search or profile child features.

If sometime in the future we do actually need some state from the store, we can start to observe
only the bare essentials of state necessary for the view to do its job. For example, suppose that 
we need access to the currently selected tab in state:

```swift
@Reducer
struct AppFeature {
  enum Tab { case activity, search, profile }
  struct State {
    var activity: Activity.State
    var search: Search.State
    var profile: Profile.State
    var selectedTab: Tab
  }
  // ...
}
```

Then we can observe this state so that we can construct a binding to `selectedTab` for the tab view:

```swift
struct AppView: View {
  let store: StoreOf<AppFeature>

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      TabView(
        selection: viewStore.binding(get: \.selectedTab, send: { .tabSelected($0) })
      ) {
        ActivityView(
          store: self.store.scope(state: \.activity, action: \.activity)
        )
        .tag(AppFeature.Tab.activity)
        SearchView(
          store: self.store.scope(state: \.search, action: \.search)
        )
        .tag(AppFeature.Tab.search)
        ProfileView(
          store: self.store.scope(state: \.profile, action: \.profile)
        )
        .tag(AppFeature.Tab.profile)
      }
    }
  }
}
```

However, this style of state observation is terribly inefficient since _every_ change to
`AppFeature.State` will cause the view to re-compute even though the only piece of state we actually
care about is the `selectedTab`. The reason we are observing too much state is because we use
`observe: { $0 }` in the construction of the ``WithViewStore``, which means the view store will
observe all of state.

To chisel away at the observed state you can provide a closure for that argument that plucks out
the state the view needs. In this case the view only needs a single field:

```swift
WithViewStore(self.store, observe: \.selectedTab) { viewStore in
  TabView(selection: viewStore.binding(send: { .tabSelected($0) }) {
    // ...
  }
}
```

In the future, the view may need access to more state. For example, suppose `Activity.State` holds
onto an `unreadCount` integer to represent how many new activities you have. There's no need to
observe _all_ of `Activity.State` to get access to this one field. You can observe just the one 
field.

Technically you can do this by mapping your state into a tuple, but because tuples are not 
`Equatable` you will need to provide an explicit `removeDuplicates` argument:

```swift
WithViewStore(
  self.store, 
  observe: { (selectedTab: $0.selectedTab, unreadActivityCount: $0.activity.unreadCount) },
  removeDuplicates: ==
) { viewStore in 
  TabView(selection: viewStore.binding(get: \.selectedTab, send: { .tabSelected($0) }) {
    ActivityView(
      store: self.store.scope(state: \.activity, action: \.activity)
    )
    .tag(AppFeature.Tab.activity)
    .badge("\(viewStore.unreadActivityCount)")

    // ...
  }
}
```

Alternatively, and recommended, you can introduce a lightweight, equatable `ViewState` struct
nested inside your view whose purpose is to transform the `Store`'s full state into the bare
essentials of what the view needs:

```swift
struct AppView: View {
  let store: StoreOf<AppFeature>
  
  struct ViewState: Equatable {
    let selectedTab: AppFeature.Tab
    let unreadActivityCount: Int
    init(state: AppFeature.State) {
      self.selectedTab = state.selectedTab
      self.unreadActivityCount = state.activity.unreadCount
    }
  }

  var body: some View {
    WithViewStore(self.store, observe: ViewState.init) { viewStore in 
      TabView {
        ActivityView(
          store: self.store
            .scope(state: \.activity, action: \.activity)
        )
        .badge("\(viewStore.unreadActivityCount)")

        // ...
      }
    }
  }
}
```

This gives you maximum flexibility in the future for adding new fields to `ViewState` without making
your view convoluted.

This technique for reducing view re-computations is most effective towards the root of your app
hierarchy and least effective towards the leaf nodes of your app. Root features tend to hold lots
of state that its view does not need, such as child features, and leaf features tend to only hold
what's necessary. If you are going to employ this technique you will get the most benefit by
applying it to views closer to the root. At leaf features and views that need access to most
of the state, it is fine to continue using `observe: { $0 }` to observe all of the state in the 
store.

### Sharing logic with actions

There is a common pattern of using actions to share logic across multiple parts of a reducer.
This is an inefficient way to share logic. Sending actions is not as lightweight of an operation
as, say, calling a method on a class. Actions travel through multiple layers of an application, and 
at each layer a reducer can intercept and reinterpret the action.

It is far better to share logic via simple methods on your ``Reducer`` conformance.
The helper methods can take `inout State` as an argument if it needs to make mutations, and it
can return an `Effect<Action>`. This allows you to share logic without incurring the cost
of sending needless actions.

For example, suppose that there are 3 UI components in your feature such that when any is changed
you want to update the corresponding field of state, but then you also want to make some mutations
and execute an effect. That common mutation and effect could be put into its own action and then
each user action can return an effect that immediately emits that shared action:

```swift
@Reducer
struct Feature {
  struct State { /* ... */ }
  enum Action { /* ... */ }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .buttonTapped:
        state.count += 1
        return .send(.sharedComputation)

      case .toggleChanged:
        state.isEnabled.toggle()
        return .send(.sharedComputation)

      case let .textFieldChanged(text):
        state.description = text
        return .send(.sharedComputation)

      case .sharedComputation:
        // Some shared work to compute something.
        return .run { send in
          // A shared effect to compute something
        }
      }
    }
  }
}
```

This is one way of sharing the logic and effect, but we are now incurring the cost of two actions
even though the user performed a single action. That is not going to be as efficient as it would
be if only a single action was sent.

Besides just performance concerns, there are two other reasons why you should not follow this 
pattern. First, this style of sharing logic is not very flexible. Because the shared logic is 
relegated to a separate action it must always be run after the initial logic. But what if
instead you need to run some shared logic _before_ the core logic? This style cannot accommodate that.

Second, this style of sharing logic also muddies tests. When you send a user action you have to 
further assert on receiving the shared action and assert on how state changed. This bloats tests
with unnecessary internal details, and the test no longer reads as a script from top-to-bottom of
actions the user is taking in the feature:

```swift
let store = TestStore(initialState: Feature.State()) {
  Feature()
}

store.send(.buttonTapped) {
  $0.count = 1
}
store.receive(\.sharedComputation) {
  // Assert on shared logic
}
store.send(.toggleChanged) {
  $0.isEnabled = true
}
store.receive(\.sharedComputation) {
  // Assert on shared logic
}
store.send(.textFieldChanged("Hello") {
  $0.description = "Hello"
}
store.receive(\.sharedComputation) {
  // Assert on shared logic
}
```

So, we do not recommend sharing logic in a reducer by having dedicated actions for the logic
and executing synchronous effects.

Instead, we recommend sharing logic with methods defined in your feature's reducer. The method has
full access to all dependencies, it can take an `inout State` if it needs to make mutations to 
state, and it can return an `Effect<Action>` if it needs to execute effects.

The above example can be refactored like so:

```swift
@Reducer
struct Feature {
  struct State { /* ... */ }
  enum Action { /* ... */ }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .buttonTapped:
        state.count += 1
        return self.sharedComputation(state: &state)

      case .toggleChanged:
        state.isEnabled.toggle()
        return self.sharedComputation(state: &state)

      case let .textFieldChanged(text):
        state.description = text
        return self.sharedComputation(state: &state)
      }
    }
  }

  func sharedComputation(state: inout State) -> Effect<Action> {
    // Some shared work to compute something.
    return .run { send in
      // A shared effect to compute something
    }
  }
}
```

This effectively works the same as before, but now when a user action is sent all logic is executed
at once without sending an additional action. This also fixes the other problems we mentioned above.

For example, if you need to execute the shared logic _before_ the core logic, you can do so easily:

```swift
case .buttonTapped:
  let sharedEffect = self.sharedComputation(state: &state)
  state.count += 1
  return sharedEffect
```

You have complete flexibility to decide how, when and where you want to execute the shared logic.

Further, tests become more streamlined since you do not have to assert on internal details of 
shared actions being sent around. The test reads  like a user script of what the user is doing
in the feature:

```swift
let store = TestStore(initialState: Feature.State()) {
  Feature()
}

store.send(.buttonTapped) {
  $0.count = 1
  // Assert on shared logic
}
store.send(.toggleChanged) {
  $0.isEnabled = true
  // Assert on shared logic
}
store.send(.textFieldChanged("Hello") {
  $0.description = "Hello"
  // Assert on shared logic
}
```

##### Sharing logic in child features

There is another common scenario for sharing logic in features where the parent feature wants to
invoke logic in a child feature. One can technically do this by sending actions from the parent 
to the child, but we do not recommend it (see above in <doc:Performance#Sharing-logic-with-actions>
to learn why):

```swift
// Handling action from parent feature:
case .buttonTapped:
  // Send action to child to perform logic:
  return .send(.child(.refresh))
```

Instead, we recommend invoking the child reducer directly:

```swift
case .buttonTapped:
  return Child().reduce(into: &state.child, action: .refresh)
    .map(Action.child)
```

### CPU intensive calculations

Reducers are run on the main thread and so they are not appropriate for performing intense CPU
work. If you need to perform lots of CPU-bound work, then it is more appropriate to use an
``Effect``, which will operate in the cooperative thread pool, and then send actions back into 
the system. You should also make sure to perform your CPU intensive work in a cooperative manner by
periodically suspending with `Task.yield()` so that you do not block a thread in the cooperative
pool for too long.

So, instead of performing intense work like this in your reducer:

```swift
case .buttonTapped:
  var result = // ...
  for value in someLargeCollection {
    // Some intense computation with value
  }
  state.result = result
```

...you should return an effect to perform that work, sprinkling in some yields every once in awhile,
and then delivering the result in an action:

```swift
case .buttonTapped:
  return .run { send in
    var result = // ...
    for (index, value) in someLargeCollection.enumerated() {
      // Some intense computation with value

      // Yield every once in awhile to cooperate in the thread pool.
      if index.isMultiple(of: 1_000) {
        await Task.yield()
      }
    }
    await send(.computationResponse(result))
  }

case let .computationResponse(result):
  state.result = result
```

This will keep CPU intense work from being performed in the reducer, and hence not on the main 
thread.

### High-frequency actions

Sending actions in a Composable Architecture application should not be thought as simple method
calls that one does with classes, such as `ObservableObject` conformances. When an action is sent
into the system there are multiple layers of features that can intercept and interpret it, and 
the resulting state changes can reverberate throughout the entire application.

Because of this, sending actions does come with a cost. You should aim to only send "significant" 
actions into the system, that is, actions that cause the execution of important logic and effects
for your application. High-frequency actions, such as sending dozens of actions per second, 
should be avoided unless your application truly needs that volume of actions in order to implement
its logic.

However, there are often times that actions are sent at a high frequency but the reducer doesn't
actually need that volume of information. For example, say you were constructing an effect that 
wanted to report its progress back to the system for each step of its work. You could choose to send
the progress for literally every step:

```swift
case .startButtonTapped:
  return .run { send in
    var count = 0
    let max = await self.eventsClient.count()

    for await event in self.eventsClient.events() {
      defer { count += 1 }
      send(.progress(Double(count) / Double(max)))
    }
  }
}
```

However, what if the effect required 10,000 steps to finish? Or 100,000? Or more? It would be 
immensely wasteful to send 100,000 actions into the system to report a progress value that is only
going to vary from 0.0 to 1.0.

Instead, you can choose to report the progress every once in awhile. You can even do the math
to make it so that you report the progress at most 100 times:

```swift
case .startButtonTapped:
  return .run { send in
    var count = 0
    let max = await self.eventsClient.count()
    let interval = max / 100

    for await event in self.eventsClient.events() {
      defer { count += 1 }
      if count.isMultiple(of: interval) {
        send(.progress(Double(count) / Double(max)))
      }
    }
  }
}
```

This greatly reduces the bandwidth of actions being sent into the system so that you are not 
incurring unnecessary costs for sending actions.

Another example that comes up often is sliders. If done in the most direct way, by deriving a 
binding from the view store to hand to a `Slider`:

```swift
Slider(value: viewStore.$opacity, in: 0...1)
```

This will send an action into the system for every little change to the slider, which can be dozens
or hundreds of actions as the user is dragging the slider. If this turns out to be problematic then
you can consider alternatives.

For example, you can hold onto some local `@State` in the view for using with the `Slider`, and
then you can use the trailing `onEditingChanged` closure to send an action to the store:

```swift
Slider(value: self.$opacity, in: 0...1) {
  self.store.send(.setOpacity(self.opacity))
}
```

This way an action is only sent once the user stops moving the slider.

### Store scoping

In the 1.5.6 release of the library a change was made to ``Store/scope(state:action:)-90255`` that
made it more sensitive to performance considerations.

The most common form of scoping, that of scoping directly along boundaries of child features, is
the most performant form of scoping and is the intended use of scoping. The library is slowly 
evolving to a state where that is the _only_ kind of scoping one can do on a store.

The simplest example of this directly scoping to some child state and actions for handing to a 
child view:

```swift
ChildView(
  store: store.scope(state: \.child, action: \.child)
)
```

Another example is scoping to some collection of a child domain in order to use with 
``ForEachStore``:

```swift
ForEachStore(store.scope(state: \.rows, action: \.rows) { store in
  RowView(store: store)
}
```

And similarly for ``IfLetStore`` and ``SwitchStore``. And finally, scoping to a child domain to be
used with one of the libraries navigation view modifiers, such as 
``SwiftUI/View/sheet(store:onDismiss:content:)``, also falls under the intended use of scope:

```swift
.sheet(store: store.scope(state: \.child, action: \.child)) { store in
  ChildView(store: store)
}
```

All of these examples are how ``Store/scope(state:action:)-90255`` is intended to be used, and you
can continue using it in this way with no performance concerns.

Where performance can become a concern is when using `scope` on _computed_ properties rather than
simple stored fields. For example, say you had a computed property in the parent feature's state
for deriving the child state:

```swift
extension ParentFeature.State {
  var computedChild: ChildFeature.State {
    ChildFeature.State(
      // Heavy computation here...
    )
  }
}
```

And then in the view, say you scoped along that computed property: 

```swift
ChildView(
  store: store.scope(state: \.computedChild, action: \.child)
)
```

If the computation in that property is heavy, it is going to become exacerbated by the changes
made in 1.5, and the problem worsens the closer the scoping is to the root of the application.

The problem is that in version 1.5 scoped stores stopped directly holding onto their local state,
and instead hold onto a reference to the store at the root of the application. And when you access
state from the scoped store, it transforms the root state to the child state on the fly.

This transformation will include the heavy computed property, and potentially compute it many times
if you need to access multiple pieces of state from the store. If you are noticing a performance
problem while depending on 1.5+ of the library, look through your code base for any place you are
using computed properties in scopes. You can even put a `print` statement in the computed property
so that you can see first hand just how many times it is being invoked while running your 
application.

To fix the problem we recommend using ``Store/scope(state:action:)-90255`` only along stored 
properties of child features. Such key paths are simple getters, and so not have a problem with
performance. If you are using a computed property in a scope, then reconsider if that could instead
be done along a plain, stored property and moving the computed logic into the child view. The 
further you push the computation towards the leaf nodes of your application, the less performance
problems you will see.

### Compiler performance

In very large SwiftUI applications you may experience degraded compiler performance causing long
compile times, and possibly even compiler failures due to "complex expressions." The
``WithViewStore``  helpers that come with the library can exacerbate that problem for very complex
views. If you are running into issues using ``WithViewStore``, there are two options for fixing
the problem.

For example, if your view looks like this:

```swift
struct FeatureView: View {
  let store: StoreOf<Feature>

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      // A large, complex view inside here...
    }
  }
}
```

…and you start running into compiler troubles, then you can explicitly specify the type of the
view store in the closure:

```swift
WithViewStore(self.store, observe: { $0 }) { (viewStore: ViewStoreOf<Feature>) in
  // A large, complex view inside here...
}
```

Or you can refactor the view to use an `@ObservedObject`:

```swift
struct FeatureView: View {
  let store: StoreOf<Feature>
  @ObservedObject var viewStore: ViewStoreOf<Feature>

  init(store: StoreOf<Feature>) {
    self.store = store
    self.viewStore = ViewStore(self.store, observe: { $0 })
  }

  var body: some View {
    // A large, complex view inside here...
  }
}
```

Both of these options should greatly improve the compiler's ability to type-check your view.
