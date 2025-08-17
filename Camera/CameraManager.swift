import SwiftUI
import Combine
import UIKit
import Foundation
import AVFoundation

@MainActor
class CameraManager: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    
    private var videoDeviceInput: AVCaptureDeviceInput? = nil

    private func flashTorch() {
        let pattern: [TimeInterval] = [0.25, 0.25, 0.16, 0.12, 0.08, 0.07, 0.07, 0.07, 0.07] // 点滅間隔

        func blink(index: Int) {
            guard index < pattern.count,
                  let device = videoDeviceInput?.device,
                  device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = .on
                try device.setTorchModeOn(level: 0.3)
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first {
                        let flashView = UIView(frame: window.bounds)
                        flashView.backgroundColor = UIColor.white
                        flashView.alpha = 0.0
                        flashView.tag = 9999
                        window.addSubview(flashView)
                        UIView.animate(withDuration: 0.03, animations: {
                            flashView.alpha = 0.8
                        }, completion: { _ in
                            UIView.animate(withDuration: pattern[index], animations: {
                                flashView.alpha = 0.0
                            }, completion: { _ in
                                flashView.removeFromSuperview()
                            })
                        })
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + pattern[index]) {
                    do {
                        try device.lockForConfiguration()
                        device.torchMode = .off
                        device.unlockForConfiguration()
                    } catch {
                        print("⚠️ フラッシュ制御失敗: \(error)")
                    }
                    if index + 1 < pattern.count {
                        blink(index: index + 1)
                    }
                }
            } catch {
                print("⚠️ フラッシュ制御失敗: \(error)")
            }
        }

        blink(index: 0)
    }
}
