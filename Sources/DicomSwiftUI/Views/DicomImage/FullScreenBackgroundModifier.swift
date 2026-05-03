import SwiftUI

struct FullScreenBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 14.0, macOS 11.0, *) {
            content.ignoresSafeArea()
        } else {
            content.edgesIgnoringSafeArea(.all)
        }
    }
}
