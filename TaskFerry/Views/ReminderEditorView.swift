import SwiftUI

struct ReminderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: AppState
    let reminder: ReminderRecord?
    @State private var title: String
    @State private var listID: String
    @State private var hasDue: Bool
    @State private var dueDate: Date
    @State private var includesTime: Bool
    @State private var confirmingDelete = false

    init(state: AppState, reminder: ReminderRecord?, defaultListID: String) {
        self.state = state
        self.reminder = reminder
        _title = State(initialValue: reminder?.title ?? "")
        _listID = State(initialValue: reminder?.listID ?? defaultListID)
        _hasDue = State(initialValue: reminder?.due != nil)
        _dueDate = State(initialValue: reminder?.due?.date() ?? Date())
        _includesTime = State(initialValue: reminder?.due?.hasTime ?? false)
    }

    var body: some View {
        VStack(spacing: 0) {
            SubviewHeader(
                title: reminder == nil ? "New Reminder" : "Edit Reminder",
                dismiss: { dismiss() }
            ) {
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || listID.isEmpty)
            }
            Divider()

            Form {
                Section("Reminder") {
                    TextField("Title", text: $title)
                    Picker("List", selection: $listID) {
                        ForEach(state.snapshot.lists) { list in
                            Text(list.title).tag(list.id)
                        }
                    }
                }
                Section("Due") {
                    Toggle("Due date", isOn: $hasDue)
                    if hasDue {
                        DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                        Toggle("Time", isOn: $includesTime)
                        if includesTime {
                            DatePicker("Time", selection: $dueDate, displayedComponents: .hourAndMinute)
                        }
                        LabeledContent("Set") {
                            ControlGroup {
                                Button("Today") { dueDate = Date(); hasDue = true }
                                Button("Tomorrow") {
                                    dueDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                                    hasDue = true
                                }
                            }
                        }
                    }
                }
                if reminder != nil {
                    Section {
                        if confirmingDelete {
                            HStack {
                                Text("Delete this reminder?")
                                Spacer()
                                Button("Cancel") { confirmingDelete = false }
                                Button("Delete", role: .destructive, action: delete)
                            }
                        } else {
                            Button("Delete Reminder", role: .destructive) { confirmingDelete = true }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
    }

    private var due: ReminderDue? {
        hasDue ? ReminderDue(date: dueDate, includesTime: includesTime) : nil
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if let reminder {
                await state.updateReminder(reminder, title: cleanTitle, listID: listID, due: due)
            } else {
                await state.createReminder(title: cleanTitle, listID: listID, due: due)
            }
            dismiss()
        }
    }

    private func delete() {
        guard let reminder else { return }
        Task {
            await state.deleteReminder(reminder)
            dismiss()
        }
    }
}
