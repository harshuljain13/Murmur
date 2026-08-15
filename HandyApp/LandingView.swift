import SwiftUI

struct LandingView: View {
    var onGetStarted: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Hero
                VStack(alignment: .leading, spacing: 16) {
                    Text("speak into\nany text field.")
                        .font(.system(size: 42, weight: .bold, design: .default))
                        .foregroundStyle(.white)
                        .lineSpacing(4)

                    Text("the free and open source app\nfor speech to text.")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)

                Spacer()

                // Feature pills
                HStack(spacing: 10) {
                    ForEach(["Free", "Open Source", "Private", "Simple"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer().frame(height: 48)

                // CTA
                Button(action: onGetStarted) {
                    HStack(spacing: 8) {
                        Text("Get Started")
                            .font(.system(size: 17, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
            }
        }
    }
}

#Preview {
    LandingView(onGetStarted: {})
}
