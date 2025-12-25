import SwiftUI

struct TimerOverlayView: View {
    let isPresented: Bool
    let message: String
    let progress: Double

    var body: some View {
        if isPresented {
            VStack(spacing: 20) {
                Text(message)
                    .font(.title)
                    .multilineTextAlignment(.center)

                // カウントダウンの数字アニメーション
                CountdownNumberView()

                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding(.horizontal)
            }
            .padding(40)
            .background(Color.white)
            .cornerRadius(20)
            .shadow(radius: 10)
        }
    }
}

// カウントダウンの数字アニメーション
struct CountdownNumberView: View {
    
    
    @State private var number: Int = 3

    var body: some View {
        Text("\(number)")
            .font(.system(size: 64, weight: .bold))
            .foregroundColor(.red)
            .onAppear {
                Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                    if number > 0 {
                        number -= 1
                    } else {
                        timer.invalidate()
                    }
                }
            }
    }
}
