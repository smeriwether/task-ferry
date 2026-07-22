import SwiftUI

struct ListsView: View {
    @Bindable var state: AppState
    @State private var newListTitle = ""

    var body: some View {
        VStack(spacing: 0) {
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
                Button("Add", action: addList)
                    .buttonStyle(.borderless)
                    .disabled(newListTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
        .navigationTitle("Lists")
    }

    private func addList() {
        let title = newListTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newListTitle = ""
        Task { await state.createList(title: title) }
    }
}

private struct ListDetailView: View {
    @Bindable var state: AppState
    let list: ReminderListRecord
    @State private var newTitle = ""

    var body: some View {
        VStack(spacing: 0) {
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
                        ReminderRowForList(state: state, reminder: reminder)
                            .contextMenu {
                                Button("Mark as Complete", systemImage: "checkmark") {
                                    Task { await state.complete(reminder) }
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }

            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(Color(hex: list.colorHex))
                TextField("New reminder", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addReminder)
                Button("Add", action: addReminder)
                    .buttonStyle(.borderless)
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
        .navigationTitle(list.title)
        .toolbar {
            NavigationLink {
                ListSettingsView(state: state, list: list)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("List settings")
        }
    }

    private var reminders: [ReminderRecord] { state.reminders(in: list.id) }

    private func addReminder() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newTitle = ""
        Task { await state.createReminder(title: title, listID: list.id, due: nil) }
    }
}

private struct ReminderRowForList: View {
    @Bindable var state: AppState
    let reminder: ReminderRecord

    var body: some View {
        HStack(spacing: 11) {
            Button {
                Task { await state.complete(reminder) }
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.indigo)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(reminder.title)")

            NavigationLink {
                ReminderEditorView(state: state, reminder: reminder, defaultListID: reminder.listID)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(reminder.title).foregroundStyle(.primary).lineLimit(2)
                    if let due = reminder.due {
                        Text(due.summary)
                            .font(.caption)
                            .foregroundStyle(due.isBeforeDay(Date()) ? .red : .secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }
}

private struct ListSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: AppState
    let list: ReminderListRecord
    @State private var title: String
    @State private var confirmingDelete = false

    init(state: AppState, list: ReminderListRecord) {
        self.state = state
        self.list = list
        _title = State(initialValue: list.title)
    }

    var body: some View {
        Form {
            Section("List") {
                TextField("Name", text: $title)
            }
            Section {
                if confirmingDelete {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Delete “\(list.title)” and its \(state.reminders(in: list.id).count) reminders?")
                            .font(.callout)
                        HStack {
                            Button("Cancel") { confirmingDelete = false }
                            Button("Delete", role: .destructive) {
                                Task {
                                    await state.deleteList(list)
                                    dismiss()
                                }
                            }
                        }
                    }
                } else {
                    Button("Delete List", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("List Settings")
        .toolbar {
            Button("Save") {
                Task {
                    await state.renameList(list, title: title)
                    dismiss()
                }
            }
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

extension ReminderDue {
    var summary: String {
        guard let date = date() else { return "Due date unavailable" }
        return hasTime
            ? date.formatted(date: .abbreviated, time: .shortened)
            : date.formatted(date: .abbreviated, time: .omitted)
    }
}
