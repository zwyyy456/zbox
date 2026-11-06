import SwiftUI

/// Search field and accessories shared by tool panels.
struct ToolSearchBar<Field: View, Accessory: View>: View {
    @ViewBuilder let field: Field
    @ViewBuilder let accessory: Accessory

    init(@ViewBuilder field: () -> Field, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.field = field()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                field
                accessory
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
        }
    }
}

/// Bottom bar keeps wrapping status above a separate row of actions.
struct ToolActionBar<Status: View, Secondary: View>: View {
    let primaryTitle: String
    let primaryKey: String
    let isPrimaryEnabled: Bool
    let primary: () -> Void
    @ViewBuilder let status: Status
    @ViewBuilder let secondary: Secondary

    init(primaryTitle: String, primaryKey: String = "↩", isPrimaryEnabled: Bool = true,
         primary: @escaping () -> Void,
         @ViewBuilder status: () -> Status = { EmptyView() },
         @ViewBuilder secondary: () -> Secondary = { EmptyView() }) {
        self.primaryTitle = primaryTitle
        self.primaryKey = primaryKey
        self.isPrimaryEnabled = isPrimaryEnabled
        self.primary = primary
        self.status = status()
        self.secondary = secondary()
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                status
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    secondary
                    Button(action: primary) {
                        HStack(spacing: 6) {
                            Text(primaryTitle)
                            Text(primaryKey).foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isPrimaryEnabled)
                }
            }
            .controlSize(.regular)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}
