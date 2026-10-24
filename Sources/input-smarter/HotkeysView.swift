import SwiftUI

/// The hotkey page of the settings window.
///
/// A hotkey is a key combination and the group of input sources it cycles
/// through. The list shows the hotkeys that exist; the editor at the bottom
/// records a new one.
struct HotkeysView: View {
    @ObservedObject var model: HotkeysViewModel

    /// The width of the label column of the editor, so that the two rows
    /// line up.
    private static let labelWidth: CGFloat = 76

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.hotkeys.isEmpty && !model.isAdding {
                emptyState
            } else {
                list
            }

            Divider()

            if model.isAdding {
                editor
            } else {
                addButton
            }
        }
    }

    // MARK: - The list

    private var header: some View {
        HStack(spacing: 8) {
            Text("快捷键")
                .font(.headline)
            Spacer(minLength: 12)
            if !model.hotkeys.isEmpty {
                Text("\(model.hotkeys.count) 个")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.hotkeys) { hotkey in
                    HotkeyRow(hotkey: hotkey, model: model)
                    Divider().padding(.leading, 12)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("还没有快捷键")
                .foregroundStyle(.secondary)
            Text("点下面的「添加快捷键」，按一个组合键就能在输入法之间轮换。")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var addButton: some View {
        Button {
            model.beginAdding()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                Text("添加快捷键")
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - The editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("按下组合键")
                    .foregroundStyle(.secondary)
                    .frame(width: Self.labelWidth, alignment: .leading)
                recorder
            }

            HStack(alignment: .top, spacing: 8) {
                Text("轮换")
                    .foregroundStyle(.secondary)
                    .frame(width: Self.labelWidth, alignment: .leading)
                    .padding(.top, 2)
                cycle
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("取消") { model.cancelAdding() }
                    .buttonStyle(.plain)
                Button("完成") { model.commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canCommit)
            }
        }
        .padding(12)
    }

    /// The field that records the key presses.
    private var recorder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .controlBackgroundColor))
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color(nsColor: .separatorColor))
            HStack(spacing: 0) {
                Text(model.draftCombo?.display ?? "点这里，然后按下组合键")
                    .font(.callout)
                    .foregroundStyle(model.draftCombo == nil ? .secondary : .primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            KeyRecorderField { combo in
                model.setDraftCombo(combo)
            }
        }
        .frame(width: 220, height: 24)
    }

    /// The input sources the hotkey cycles through, in order.
    private var cycle: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.draftSources.isEmpty {
                Text("还没有选输入法")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.draftSources.enumerated()), id: \.element) { index, id in
                    HStack(spacing: 6) {
                        Text("\(index + 1).")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                        Text(model.name(of: id))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button {
                            model.removeDraftSource(id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Menu {
                ForEach(model.availableSources) { source in
                    Button(source.displayName) {
                        model.addDraftSource(source.id.composite)
                    }
                }
            } label: {
                Label("添加输入法", systemImage: "plus.circle")
                    .font(.callout)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(model.availableSources.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One hotkey: the combination and the input sources it cycles through.
struct HotkeyRow: View {
    let hotkey: HotkeyBinding
    @ObservedObject var model: HotkeysViewModel

    var body: some View {
        HStack(spacing: 10) {
            Text(KeyCombo(keyCode: hotkey.keyCode, modifiers: hotkey.modifiers).display)
                .frame(width: 90, alignment: .leading)

            Text(hotkey.inputSourceIDs.map { model.name(of: $0) }.joined(separator: " → "))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Button {
                model.remove(hotkey)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("删除这个快捷键")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}
