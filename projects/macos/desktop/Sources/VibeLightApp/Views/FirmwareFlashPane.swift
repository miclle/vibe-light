import SwiftUI

struct FirmwareFlashPane: View {
    @ObservedObject var model: VibeLightAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                FirmwareFlashWizardCard(model: model)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
            .frame(maxWidth: 1180, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle("固件烧录")
    }
}
