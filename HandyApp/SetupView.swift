import SwiftUI

struct SetupView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                VStack(alignment: .leading, spacing: 10) {
                    Text("one last step.")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                    Text("enable the handy keyboard in iOS Settings.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .padding(.horizontal, 28)
                .padding(.top, 56)
                .padding(.bottom, 40)

                VStack(spacing: 12) {
                    StepRow(number: "1", text: "Open **Settings → General → Keyboard → Keyboards**")
                    StepRow(number: "2", text: "Tap **Add New Keyboard**")
                    StepRow(number: "3", text: "Select **Handy**")
                    StepRow(number: "4", text: "Tap **Handy** again and turn on **Allow Full Access**\n(required for microphone in keyboard)")
                }
                .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open Settings")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Text("After enabling, open any app (e.g. WhatsApp), tap a text field, switch to Handy keyboard, and tap the mic.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
            }
        }
    }
}

private struct StepRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(Color.white)
                .clipShape(Circle())

            Text(.init(text))
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    SetupView()
}
