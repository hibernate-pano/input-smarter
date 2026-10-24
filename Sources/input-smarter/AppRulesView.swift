import AppKit
import SwiftUI

/// The app list of the settings window.
///
/// The menu bar can only bind the app that is frontmost right now; this
/// window is where a rule for any installed app is created.
///
/// Only the apps that have a rule are listed. The rest is noise: the user
/// configures a handful of apps, and adds them one at a time.
struct AppRulesView: View {
    @ObservedObject var model: AppRulesViewModel

    var body: some View {
        Group {
            if model.isPicking {
                picker
            } else {
                list
            }
        }
        .frame(minWidth: 560, minHeight: 400)
    }

    // MARK: - The list of the configured apps

    private var list: some View {
        VStack(spacing: 0) {
            header(
                title: "已配置的 app",
                trailing: model.rows.isEmpty ? "" : "\(model.rows.count) 个"
            )
            Divider()

            if model.rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    // A lazy stack: only the rows on screen are built, so the
                    // icons are not loaded for rows that are out of sight.
                    LazyVStack(spacing: 0) {
                        ForEach(model.rows) { row in
                            AppRuleRow(row: row, model: model)
                            Divider().padding(.leading, 42)
                        }
                    }
                }
            }

            Divider()
            addButton
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("还没有配置任何 app")
                .foregroundStyle(.secondary)
            Text("点下面的「添加 app」，挑一个 app 固定输入法。")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var addButton: some View {
        Button {
            model.searchText = ""
            model.isPicking = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                Text("添加 app")
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - The picker

    private var picker: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索 app", text: $model.searchText)
                    .textFieldStyle(.plain)
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button("取消") {
                    model.isPicking = false
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()

            if model.visibleCandidates.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text(model.candidates.isEmpty ? "所有 app 都已配置" : "没有找到 app")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.visibleCandidates) { app in
                            CandidateRow(app: app, model: model)
                            Divider().padding(.leading, 42)
                        }
                    }
                }
            }
        }
    }

    private func header(title: String, trailing: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
            Spacer(minLength: 12)
            if model.isLoading {
                Text("正在读取…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if !trailing.isEmpty {
                Text(trailing)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// One app and the input source it is bound to.
struct AppRuleRow: View {
    let row: AppListRow
    @ObservedObject var model: AppRulesViewModel

    var body: some View {
        HStack(spacing: 10) {
            AppIcon(image: model.icons[row.bundleID])
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .lineLimit(1)
                if !row.isInstalled {
                    Text("未安装")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Picker("", selection: selection) {
                // Picking it takes the rule away: the app goes back to the
                // system's default and leaves the list.
                Text("恢复默认").tag("")
                ForEach(model.sources) { source in
                    Text(source.displayName).tag(source.id.composite)
                }
                // A rule can point at an input source that is gone. It still
                // has to be visible, or the row would show nothing at all.
                if let bound = row.boundSourceID,
                   !model.sources.contains(where: { $0.id.composite == bound }) {
                    Text("\(model.shortName(of: bound))（已失效）").tag(bound)
                }
            }
            .labelsHidden()
            .frame(width: 170)

            Button {
                model.unbind(row)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("恢复默认")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .task(id: row.url) {
            model.loadIcon(bundleID: row.bundleID, url: row.url)
        }
        .contextMenu {
            Toggle("离开这个 app 时恢复输入法", isOn: restoreBinding)
            Divider()
            Button("恢复默认（移除这条配置）") { model.unbind(row) }
        }
    }

    /// The chosen input source; an empty string means "the system's default".
    private var selection: Binding<String> {
        Binding(
            get: { row.boundSourceID ?? "" },
            set: { model.bind(row, to: $0.isEmpty ? nil : $0) }
        )
    }

    private var restoreBinding: Binding<Bool> {
        Binding(
            get: { model.restoresOnLeave(row) },
            set: { model.setRestore(row, restore: $0) }
        )
    }
}

/// One app that can still be added.
struct CandidateRow: View {
    let app: InstalledApp
    @ObservedObject var model: AppRulesViewModel

    var body: some View {
        Button {
            model.add(app)
            model.isPicking = false
        } label: {
            HStack(spacing: 10) {
                AppIcon(image: model.icons[app.bundleID])
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.displayName)
                        .lineLimit(1)
                    Text(app.bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .task(id: app.url) {
            model.loadIcon(bundleID: app.bundleID, url: app.url)
        }
    }
}

/// The icon of an app.
struct AppIcon: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
