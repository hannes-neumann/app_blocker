import AppKit
import SwiftUI

private struct ProjectAppIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "app.dashed").frame(width: 20, height: 20)
        }
    }
}

struct ProjectsView: View {
    @Environment(AppState.self) private var state
    @State private var selectedID: UUID?
    @State private var newProject = ""

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(state.projects.projects) { project in
                    Label(project.name, systemImage: "folder")
                        .tag(project.id)
                }
            }

            .frame(width: 220)
            .overlay(alignment: .bottom) {
                HStack {
                    TextField("Neues Projekt", text: $newProject)
                        .onSubmit(addProject)
                    Button(action: addProject) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(newProject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(10)
                .background(.bar)
            }

            if let id = selectedID, let project = state.projects.project(id) {
                ProjectDetail(project: project)
            } else {
                ContentUnavailableView("Wähle ein Projekt", systemImage: "folder",
                                       description: Text("Lege ein Projekt an, um konkrete Aufgaben und App-Regeln zu verwalten."))
            }
        }
        .onAppear { selectedID = selectedID ?? state.projects.projects.first?.id }
    }

    private func addProject() {
        state.projects.add(newProject)
        newProject = ""
        selectedID = state.projects.projects.first?.id
    }
}

private struct ProjectDetail: View {
    @Environment(AppState.self) private var state
    let project: Project
    @State private var taskTitle = ""
    @State private var name = ""

    private var tasks: [Todo] {
        state.todos.todos.filter { $0.projectID == project.id }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    TextField("Projektname", text: $name)
                        .font(.title2.weight(.semibold))
                        .textFieldStyle(.plain)
                        .onSubmit(rename)
                    Button(L10n.text("save"), action: rename)
                    Spacer()
                    Button(L10n.text("delete"), role: .destructive) {
                        state.projects.delete(project.id)
                    }
                }
                Text(L10n.text("tasks")).font(.headline)
                HStack {
                    TextField("Neue Aufgabe, z. B. Kapitel 2 zusammenfassen", text: $taskTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addTask)
                    Button(L10n.text("add"), action: addTask)
                        .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if tasks.isEmpty {
                    Text("Noch keine Aufgaben in diesem Projekt.").foregroundStyle(.secondary)
                } else {
                    ForEach(tasks) { task in
                        TaskRow(task: task, project: project)
                        Divider()
                    }
                }
                Divider()
                AppOverrideEditor(title: "Apps für dieses Projekt", value: project.blockedApps) {
                    state.projects.setBlockedApps($0, for: project.id)
                }
            }
            .padding(24)
        }
        .onAppear { name = project.name }
        .onChange(of: project.name) { _, value in name = value }
    }

    private func rename() {
        state.projects.rename(project.id, name: name)
    }

    private func addTask() {
        state.todos.addTask(title: taskTitle, projectID: project.id)
        taskTitle = ""
    }
}

private struct TaskRow: View {
    @Environment(AppState.self) private var state
    let task: Todo
    let project: Project
    @State private var expanded = false
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { state.todos.toggleDone(task.id, source: "projects") } label: {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.isDone ? .green : .secondary)
                }.buttonStyle(.plain)
                TextField("Aufgabe", text: $title)
                    .textFieldStyle(.plain)
                    .strikethrough(task.isDone)
                    .onSubmit { state.todos.setTitle(task.id, title: title) }
                Spacer()
                Button { expanded.toggle() } label: {
                    Label(L10n.text("apps"), systemImage: "app.dashed")
                }.buttonStyle(.borderless)
                Button { state.todos.delete(task.id, source: "projects") } label: {
                    Image(systemName: "trash")
                }.buttonStyle(.plain)
            }
            if expanded {
                AppOverrideEditor(title: "Apps für diese Aufgabe", value: task.blockedApps) {
                    state.todos.setBlockedApps($0, for: task.id)
                }
            }
        }
        .padding(.vertical, 5)
        .onAppear { title = task.title }
        .onChange(of: task.title) { _, value in title = value }
    }
}

private struct AppOverrideEditor: View {
    let title: String
    let value: [BlockedApp]?
    let onChange: ([BlockedApp]?) -> Void
    @State private var custom = false
    @State private var apps: [BlockedApp] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L10n.text("ownAppRule"), isOn: $custom)
                .onChange(of: custom) { _, enabled in onChange(enabled ? apps : nil) }
            if custom {
                if apps.isEmpty {
                    Text(L10n.text("noBlockedApps")).foregroundStyle(.secondary)
                }
                ForEach(apps) { app in
                    HStack {
                        ProjectAppIcon(bundleID: app.bundleID)
                        Text(app.name)
                        Spacer()
                        Button { apps.removeAll { $0 == app }; onChange(apps) } label: {
                            Image(systemName: "minus.circle.fill")
                        }.buttonStyle(.plain)
                    }

                }
                HStack {
                    Button("App auswählen…", action: chooseApps)
                    Menu("Laufende App") {
                        ForEach(runningApps, id: \.bundleID) { app in
                            Button(app.name) { apps.append(app); onChange(apps) }
                        }
                    }

                }
            } else {
                Text(L10n.text("inheritRule")).font(.caption).foregroundStyle(.secondary)
            }

        }
        .onAppear { custom = value != nil; apps = value ?? [] }
    }

    private var runningApps: [BlockedApp] {
        let existing = Set(apps.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, !existing.contains(id) else { return nil }
                return BlockedApp(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  !apps.contains(where: { $0.bundleID == id }) else { continue }
            apps.append(BlockedApp(bundleID: id,
                                   name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")))
        }
        onChange(apps)
    }
}
