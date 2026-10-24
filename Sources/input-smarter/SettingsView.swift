import Combine
import SwiftUI

/// The pages of the settings window.
///
/// Each page holds one thing, so neither of them can turn into a wall of
/// switches.
enum SettingsPage: String, CaseIterable, Hashable {
    case apps
    case hotkeys

    var title: String {
        switch self {
        case .apps: return "应用"
        case .hotkeys: return "快捷键"
        }
    }
}

/// Drives the settings window.
@MainActor
final class SettingsViewModel: ObservableObject {
    /// The page that is shown.
    @Published var page: SettingsPage = .apps

    /// The app rules.
    let appRules: AppRulesViewModel
    /// The hotkeys.
    let hotkeys: HotkeysViewModel

    init(store: RuleStore, installed: [InstalledApp], sources: [InputSourceInfo]) {
        appRules = AppRulesViewModel(store: store, installed: installed, sources: sources)
        hotkeys = HotkeysViewModel(store: store, sources: sources)
    }

    /// Show a page.
    ///
    /// The app picker belongs to the app page: leaving that page closes it.
    func show(_ page: SettingsPage) {
        self.page = page
        if page != .apps { appRules.isPicking = false }
    }

    /// Hand over the input sources.
    func setSources(_ sources: [InputSourceInfo]) {
        appRules.setSources(sources)
        hotkeys.setSources(sources)
    }

    /// Read the configuration again.
    func reload() {
        appRules.reload()
        hotkeys.reload()
    }
}

/// The settings window.
///
/// The pages are switched with a segmented control at the top: the app list
/// on one side, the hotkeys on the other.
struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            // The app picker takes over the whole window while it is open.
            if !model.appRules.isPicking {
                switcher
                Divider()
            }

            switch model.page {
            case .apps:
                AppRulesView(model: model.appRules)
            case .hotkeys:
                HotkeysView(model: model.hotkeys)
            }
        }
        .frame(minWidth: 560, minHeight: 400)
    }

    private var switcher: some View {
        HStack(spacing: 0) {
            Picker("", selection: pageBinding) {
                ForEach(SettingsPage.allCases, id: \.self) { page in
                    Text(page.title).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var pageBinding: Binding<SettingsPage> {
        Binding(
            get: { model.page },
            set: { model.show($0) }
        )
    }
}
