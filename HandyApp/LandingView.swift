import SwiftUI

struct LandingView: View {
    var onGetStarted: () -> Void

    var body: some View {
        ZStack {
            Handy.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                Image("HandyLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .padding(.bottom, 28)

                // Hero
                VStack(alignment: .leading, spacing: 16) {
                    Text("speak into\nany text field.")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Handy.cream)
                        .lineSpacing(4)

                    Text("the free and open source app\nfor speech to text.")
                        .font(.system(size: 18))
                        .foregroundStyle(Handy.text(0.55))
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
                            .foregroundStyle(Handy.pinkLight)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Handy.pink.opacity(0.14))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer().frame(height: 40)

                // CTA
                Button(action: onGetStarted) {
                    HStack(spacing: 8) {
                        Text("Get Started")
                            .font(.system(size: 17, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Handy.pinkDeep)
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
