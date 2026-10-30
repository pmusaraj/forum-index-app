import SwiftUI

/// iOS hides a segmented picker's label, so show it above the control explicitly.
struct SettingsSegmentedPicker<Selection: Hashable, Options: View>: View {
    let title: LocalizedStringKey
    @Binding var selection: Selection
    let accessibilityID: String
    @ViewBuilder let options: () -> Options

    var body: some View {
#if os(iOS)
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            Picker(title, selection: $selection, content: options)
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier(accessibilityID)
        }
#else
        Picker(title, selection: $selection, content: options)
            .pickerStyle(.segmented)
            .accessibilityIdentifier(accessibilityID)
#endif
    }
}
