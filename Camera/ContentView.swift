import SwiftUI

struct ContentView: View {
    // CameraManagerの状態を親Viewから渡す
    @StateObject var cameraManager = CameraManager()
    
    var body: some View {
        CameraPreviewView(cameraManager: cameraManager)
    }
}

