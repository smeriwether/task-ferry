import SwiftUI

struct ListsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: AppState
    @State private var newListTitle = ""
    @State private var isAddingList = false

    var body: some View {
        VStack(spacing: 0) {
            SubviewHeader(title: "Lists", dismiss: { dismiss() })
            Divider()

            if let error = state.errorMessage {
                ErrorBanner(message: error) { state.dismissError() }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            List {
                ForEach(state.snapshot.lists) { list in
                    NavigationLink {
                        ListDetailView(state: state, list: list)
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(Color(hex: list.colorHex)).frame(width: 9, height: 9)
                            Text(list.title)
                            Spacer()
                            Text("\(state.reminders(in: list.id).count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.inset)

            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(.indigo)
                TextField("New list", text: $newListTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addList)
                    .disabled(isAddingList)
                Button(isAddingList ? "Adding…" : "Add", action: addList)
                    .buttonStyle(.borderless)
                    .disabled(isAddingList || newListTitle.trimmed.isEmpty)
            }
            .padding(12)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
    }

    private func addList() {
        let title = newListTitle.trimmed
        guard !title.isEmpty, !isAddingList else { return }
        isAddingList = true
        Task {
            if await state.createList(title: title) {
                newListTitle = ""
            }
            isAddingList = false
        }
    }
}

private struct ListDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: AppState
    let list: ReminderListRecord
    @State private var newTitle = ""
    @State private var isAddingReminder = false

    var body: some View {
        VStack(spacing: 0) {
            SubviewHeader(title: list.title, dismiss: { dismiss() }) {
                NavigationLink {
                    ListSettingsView(state: state, list: list)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("List settings")
            }
            Divider()

            if let error = state.errorMessage {
                ErrorBanner(message: error) { state.dismissError() }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            if reminders.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "Nothing here",
                    systemImage: "tray",
                    description: Text("Add the first reminder below.")
                )
                Spacer()
            } else {
                List {
                    ForEach(reminders) { reminder in
                        ReminderRow(state: state, reminder: reminder, context: .list)
                    }
                }
                .listStyle(.inset)
            }

            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(Color(hex: list.colorHex))
                TextField("New reminder", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addReminder)
                    .disabled(isAddingReminder)
                Button(isAddingReminder ? "Adding…" : "Add", action: addReminder)
                    .buttonStyle(.borderless)
                    .disabled(isAddingReminder || newTitle.trimmed.isEmpty)
            }
            .padding(12)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
    }

    private var reminders: [ReminderRecord] { state.reminders(in: list.id) }

    private func addReminder() {
        let title = newTitle.trimmed
        guard !title.isEmpty, !isAddingReminder else { return }
        isAddingReminder = true
        Task {
            if await state.createReminder(title: title, listID: list.id, due: nil) {
                newTitle = ""
            }
            isAddingReminder = false
        }
    }
}

private struct ListSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: AppState
    let list: ReminderListRecord
    @State private var title: String
    @State private var confirmingDelete = false
    @State private var isSaving = false
    @State private var isDeleting = false

    init(state: AppState, list: ReminderListRecord) {
        self.state = state
        self.list = list
        _title = State(initialValue: list.title)
    }

    var body: some View {
        VStack(spacing: 0) {
            SubviewHeader(title: "List Settings", dismiss: { dismiss() }) {
                Button(isSaving ? "Saving…" : "Save", action: save)
                    .disabled(isSaving || isDeleting || title.trimmed.isEmpty)
            }
            Divider()

            if let error = state.errorMessage {
                ErrorBanner(message: error) { state.dismissError() }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            Form {
                Section("List") {
                    TextField("Name", text: $title)
                }
                Section {
                    if confirmingDelete {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Delete “\(list.title)” and all of its reminders, including completed reminders?")
                            .font(.callout)
                            HStack {
                                Button("Cancel") { confirmingDelete = false }
                                    .disabled(isDeleting)
                                Button(isDeleting ? "Deleting…" : "Delete", role: .destructive) {
                                    guard !isDeleting, !isSaving else { return }
                                    isDeleting = true
                                    Task {
                                        if await state.deleteList(list) {
                                            dismiss()
                                        } else {
                                            isDeleting = false
                                        }
                                    }
                                }
                                .disabled(isDeleting || isSaving)
                            }
                        }
                    } else {
                        Button("Delete List", role: .destructive) { confirmingDelete = true }
                            .disabled(isSaving)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
    }

    private func save() {
        guard !isSaving, !isDeleting else { return }
        let cleanTitle = title.trimmed
        isSaving = true
        Task {
            if await state.renameList(list, title: cleanTitle) {
                dismiss()
            } else {
                isSaving = false
            }
        }
    }
}

struct SubviewHeader<Trailing: View>: View {
    let title: String
    let dismiss: () -> Void
    let trailing: Trailing

    init(title: String, dismiss: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.dismiss = dismiss
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: dismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back")
            .accessibilityLabel("Back")

            Text(title)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

extension SubviewHeader where Trailing == EmptyView {
    init(title: String, dismiss: @escaping () -> Void) {
        self.init(title: title, dismiss: dismiss) { EmptyView() }
    }
}
