import SwiftUI

struct PlaceholderScreen: View {
    let title: String
    let note: String
    var body: some View {
        Screen(title: title) { Caption(note) }
    }
}
