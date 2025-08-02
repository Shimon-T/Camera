//
//  ContentView.swift
//  Camera
//
//  Created by 田中志門 on 7/12/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
//        TimerTestView()
        let cameraManager = CameraManager()
        CameraPreviewView(cameraManager: cameraManager)
    }
}
