import SwiftUI

@main
struct KnoxCanvasApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(red: 0.059, green: 0.067, blue: 0.090).ignoresSafeArea()
                Text("KnoxCanvas").font(.largeTitle.bold()).foregroundStyle(.white)
            }
            .preferredColorScheme(.dark)
        }
    }
}
