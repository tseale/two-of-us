import SwiftUI

/// Data for the transient "Logged · Undo" toast.
struct ToastData: Identifiable, Equatable {
    let id = UUID()
    let message: String
    /// Tint for the Undo button, so it matches the event that was logged
    /// (feed teal / diaper amber / sleep periwinkle) instead of always feed teal.
    var accent: Color = AppColor.accentFeed
    let undo: () -> Void

    static func == (lhs: ToastData, rhs: ToastData) -> Bool { lhs.id == rhs.id }
}

private struct LoggedToastModifier: ViewModifier {
    @Binding var toast: ToastData?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast {
                HStack(spacing: 14) {
                    Text(toast.message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.text)
                    Spacer()
                    Button("Undo") {
                        toast.undo()
                        Haptics.tap()
                        self.toast = nil
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(toast.accent)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(AppColor.card2, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { self.toast = nil }
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: toast)
    }
}

extension View {
    func loggedToast(_ toast: Binding<ToastData?>) -> some View {
        modifier(LoggedToastModifier(toast: toast))
    }
}
