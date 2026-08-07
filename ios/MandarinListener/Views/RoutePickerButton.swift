import AVKit
import SwiftUI

struct RoutePickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.activeTintColor = .systemCyan
        picker.tintColor = .white
        return picker
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
