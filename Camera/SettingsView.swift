//
//  SettingsView.swift
//  Camera
//
//  Created by 田中志門 on 7/12/25.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("gestureEnabled") var gestureEnabled: Bool = true

    var body: some View {
        Form {
            Toggle("ジェスチャーで撮影", isOn: $gestureEnabled)
        }
        .navigationTitle("設定")
    }
}

#Preview {
    SettingsView()
}
