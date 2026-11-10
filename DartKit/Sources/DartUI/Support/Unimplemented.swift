func unimplemented(_ function: StaticString = #function) -> Never {
    fatalError("unimplemented: \(function)")
}

import SwiftUI

/// Placeholder body of a view that is not written yet.
struct StubView: View {
    var body: some View { EmptyView() }
}
