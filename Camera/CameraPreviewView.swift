//
//  CameraPreviewView.swift
//  Camera
//
//  Created by 田中志門 on 7/12/25.
//

import SwiftUI

struct CameraPreviewView: View {
    @ObservedObject var cameraManager: CameraManager
    @State private var smoothProgressTime: TimeInterval = 0.0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            // カメラ映像の表示
            CameraView(session: cameraManager.session)
                .ignoresSafeArea()

            // タイマー
            if let purpose = cameraManager.timerPurpose {
                let totalTime = 3.0
                let elapsed = min(smoothProgressTime, totalTime)
                let color: Color = elapsed < 1.5 ? .orange : .green
                let displayProgress = min(elapsed / totalTime, 1.0)
                CircularTimerComponent(
                    progress: displayProgress,
                    totalTime: 3,
                    color: color
                )
                .frame(width: 150, height: 150)
                .position(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2)
                .zIndex(998)
                .transition(.scale)
                .animation(.easeInOut(duration: 0.1), value: cameraManager.timerCount)
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
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
        .onChange(of: cameraManager.timerPurpose) { newValue in
            timer?.invalidate()
            timer = nil
            if newValue != nil {
                smoothProgressTime = 0.0
                timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
                    DispatchQueue.main.async {
                        if smoothProgressTime < 3.0 {
                            smoothProgressTime += 0.02
                        } else {
                            timer?.invalidate()
                            timer = nil
                        }
                    }
                }
            }
            if newValue == .gestureHold {
                print("🟠 検出タイマー開始: 残り \(cameraManager.timerCount) 秒")
            } else if newValue == .captureDelay {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("🟢 撮影タイマー開始: 残り \(cameraManager.timerCount) 秒")
                }
            }
        }
    }
}
