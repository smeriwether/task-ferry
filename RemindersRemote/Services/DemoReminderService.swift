import Foundation

@MainActor
final class DemoReminderService: ReminderService {
    private var value: ReminderSnapshot

    init(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        let today = ReminderDue(date: now, includesTime: false, calendar: calendar)
        let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let tomorrow = ReminderDue(date: tomorrowDate, includesTime: false, calendar: calendar)
        let overdueDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let overdue = ReminderDue(date: overdueDate, includesTime: false, calendar: calendar)
        value = ReminderSnapshot(
            lists: [
                ReminderListRecord(id: "personal", title: "Personal", colorHex: "5E5CE6"),
                ReminderListRecord(id: "work", title: "Work", colorHex: "0A84FF")
            ],
            reminders: [
                ReminderRecord(id: "1", listID: "work", title: "Send the quarterly report", due: today),
                ReminderRecord(id: "2", listID: "personal", title: "Renew prescription", due: today),
                ReminderRecord(id: "3", listID: "personal", title: "Call the dentist", due: overdue),
                ReminderRecord(id: "4", listID: "work", title: "Prepare tomorrow’s notes", due: tomorrow)
            ]
        )
    }

    func execute(_ request: RPCRequest) async throws -> ReminderSnapshot {
        switch request.operation {
        case .snapshot:
            break
        case .upsertList:
            guard let title = request.title?.trimmed, !title.isEmpty else {
                throw ReminderServiceError.message("A list needs a name.")
            }
            if let id = request.id, let index = value.lists.firstIndex(where: { $0.id == id }) {
                value.lists[index].title = title
            } else {
                value.lists.append(ReminderListRecord(id: UUID().uuidString, title: title, colorHex: "30D158"))
            }
        case .deleteList:
            guard let id = request.id else { break }
            value.lists.removeAll { $0.id == id }
            value.reminders.removeAll { $0.listID == id }
        case .upsertReminder:
            guard let title = request.title?.trimmed, !title.isEmpty,
                  let listID = request.listID else {
                throw ReminderServiceError.message("A reminder needs a title and list.")
            }
            if let id = request.id, let index = value.reminders.firstIndex(where: { $0.id == id }) {
                value.reminders[index].title = title
                value.reminders[index].listID = listID
                value.reminders[index].due = request.due
            } else {
                value.reminders.append(ReminderRecord(
                    id: UUID().uuidString,
                    listID: listID,
                    title: title,
                    due: request.due
                ))
            }
        case .setCompleted:
            if request.completed == true, let id = request.id {
                value.reminders.removeAll { $0.id == id }
            }
        case .deleteReminder:
            if let id = request.id {
                value.reminders.removeAll { $0.id == id }
            }
        }
        value.lists.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return value
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
