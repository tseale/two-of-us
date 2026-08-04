import SwiftUI
import SwiftData

/// "About" subpage: app icon, version, and the credit line.
struct AboutSettingsView: View {
    @Query private var babies: [Baby]

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    AppIconBadge(size: 60)
                    Text("Two of Us")
                        .font(AppFont.hero(20))
                        .foregroundStyle(AppColor.text)
                    Text(AppInfo.versionString)
                        .font(.caption)
                        .foregroundStyle(AppColor.text3)
                    Text("Made with love for \(babies.first?.name ?? "your little one") 🤍")
                        .font(.footnote)
                        .foregroundStyle(AppColor.text2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
