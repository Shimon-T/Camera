//
//  TimerOverlayView.swift
//  Camera
//
//  Created by 田中志門 on 7/12/25.
//

import SwiftUI

struct TimerOverlayView: View {
    let timeRemaining: Int

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.4)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .edgesIgnoringSafeArea(.all)

                Text("\(timeRemaining)")
                    .font(.system(size: 100, weight: .bold))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
                    .shadow(radius: 10)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .zIndex(999)
        }
    }
}
