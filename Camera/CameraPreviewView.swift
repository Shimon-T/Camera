//
//  CameraPreviewView.swift
//  Camera
//
//  Created by 田中志門 on 7/12/25.
//

import SwiftUI

struct CameraPreviewView: View {
    @StateObject var cameraManager = CameraManager()

    var body: some View {
        ZStack {
            // カメラ映像の表示
            CameraView(session: cameraManager.session)
                .ignoresSafeArea()

            // タイマー
            if cameraManager.timerCount > 0 {
                CircularTimerComponent(
                    progress: 1.0 - Double(cameraManager.timerCount) / Double(max(cameraManager.timerTotal, 1)),
                    totalTime: cameraManager.timerTotal
                )
                .frame(width: 150, height: 150)
                .position(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2)
                .zIndex(998)
                .transition(.scale)
            }

            // 録画中インジケーター
            if cameraManager.isRecording {
                VStack {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                        Text("録画中: \(cameraManager.recordingDuration) 秒")
                            .foregroundColor(.white)
                            .bold()
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    Spacer()
                }
                .padding(.top, 50)
                .padding(.horizontal)
            }

            // テスト用の手動操作ボタン
            VStack {
                Spacer()
                HStack(spacing: 20) {
                    Button("📸 撮影開始（テスト）") {
                        cameraManager.triggerCountdownAndCapture()
                    }
                    Button("🔄 カメラ切替") {
                        cameraManager.switchCamera()
                    }
                    Button("🛑 停止") {
                        cameraManager.stopTimerOrRecording()
                    }
                }
                .padding()
                .background(Color.white.opacity(0.9))
                .cornerRadius(12)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            cameraManager.startSession()
            cameraManager.startHandDetection()
        }
        .onChange(of: cameraManager.timerCount) { newValue in
            if newValue > 0 {
                print("⏳ タイマースタート: 残り \(newValue) 秒")
            }
        }
    }
}
