import SwiftUI

struct QuickEntryView: View {
    @Bindable var state: AppState
    @State private var title = ""
    @State private var listID = ""
    @State private var due = QuickDue.today
    @State private var isSubmitting = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Quick Reminder", systemImage: "plus.circle.fill")
                .font(.headline)

            if state.mode == nil {
                Text("Finish setup in the Task Ferry window first.")
                    .foregroundStyle(.secondary)
            } else if state.snapshot.lists.isEmpty {
                ProgressView("Loading lists…")
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                TextField("What needs doing?", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($titleFocused)
                    .onSubmit(addReminder)
                    .disabled(isSubmitting)

                Picker("List", selection: $listID) {
                    ForEach(state.snapshot.lists) { list in
                        Text(list.title).tag(list.id)
                    }
                }
                .disabled(isSubmitting)

                Picker("Due", selection: $due) {
                    ForEach(QuickDue.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isSubmitting)

                Button(isSubmitting ? "Adding…" : "Add Reminder", action: addReminder)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .disabled(isSubmitting || title.trimmed.isEmpty || listID.isEmpty)
            }

            if let error = state.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(width: 340)
        .task {
            due = .today
            await state.refresh()
            selectDefaultListIfNeeded()
            titleFocused = true
        }
        .onChange(of: state.snapshot.lists) { _, _ in selectDefaultListIfNeeded() }
    }

    private func addReminder() {
        let reminderTitle = title.trimmed
        guard !reminderTitle.isEmpty, !listID.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        Task {
            let succeeded = await state.createReminder(title: reminderTitle, listID: listID, due: due.value)
            if succeeded {
                title = ""
            }
            isSubmitting = false
            titleFocused = true
        }
    }

    private func selectDefaultListIfNeeded() {
        guard !state.snapshot.lists.contains(where: { $0.id == listID }) else { return }
        listID = state.defaultListID ?? ""
    }
}

private enum QuickDue: String, CaseIterable, Identifiable {
    case none, today, tomorrow

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var value: ReminderDue? {
        guard self != .none else { return nil }
        let date = self == .today
            ? Date()
            : (Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        return ReminderDue(date: date, includesTime: false)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
