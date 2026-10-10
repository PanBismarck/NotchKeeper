import ServiceManagement
import SwiftUI

struct SettingsView: View {
    static let windowID = "settings"

    @Bindable var settings: AppSettings
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var screens: [String] = []

    var body: some View {
        Form {
            Section("Ogólne") {
                Toggle("Uruchamiaj przy logowaniu", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Picker("Skrót otwierający wyspę", selection: $settings.shortcut) {
                    ForEach(AppSettings.Shortcut.allCases) { Text($0.label).tag($0) }
                }
                Picker("Ekran", selection: $settings.screenName) {
                    Text("Z notchem (automatycznie)").tag("")
                    ForEach(screens, id: \.self) { Text($0).tag($0) }
                }
            }

            Section("Wyspa") {
                Toggle("Rozwijaj po najechaniu kursorem", isOn: $settings.hoverToExpand)
                Toggle("Chowaj, gdy aplikacja jest na pełnym ekranie", isOn: $settings.hideInFullScreen)
                    .help("Czekające uprawnienie i tak pokaże wyspę")
                Toggle("Na pełnym ekranie: najechanie na notch pokazuje wyspę", isOn: $settings.peekInFullScreen)
                    .help("Wyspa chowa się w notchu: najechanie wysuwa skrzydełka, kliknięcie otwiera")
                    .disabled(!settings.hideInFullScreen)
                Toggle("Efekt szkła (Liquid Glass)", isOn: $settings.glassIsland)
                Toggle("Przezroczystość jak w systemie", isOn: $settings.glassFollowsSystem)
                    .help("Ustawienia systemowe → Wygląd → Liquid Glass; „Zmniejsz przezroczystość” też działa")
                    .disabled(!settings.glassIsland)
                LabeledContent("Przezroczystość szkła") {
                    Slider(value: $settings.glassIntensity, in: 0...1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Image(systemName: "circle.fill")
                    } maximumValueLabel: {
                        Image(systemName: "circle.dotted")
                    }
                    .frame(width: 180)
                }
                .disabled(!settings.glassIsland || settings.glassFollowsSystem)
                Picker("Zwijaj po zjechaniu kursorem", selection: $settings.collapseDelay) {
                    Text("Od razu").tag(0.3)
                    Text("Po 1 s").tag(1.0)
                    Text("Po 3 s").tag(3.0)
                }
                Picker("Wynik sesji widoczny", selection: $settings.finishedLinger) {
                    Text("30 s").tag(30.0)
                    Text("2 min").tag(120.0)
                    Text("5 min").tag(300.0)
                }
            }

            Section("Dźwięki") {
                Toggle("Graj dźwięki", isOn: $settings.soundsEnabled)
                soundPicker("Czeka na Ciebie", $settings.waitingSound)
                soundPicker("Gotowe", $settings.doneSound)
            }

            Section("Claude Code") {
                LabeledContent("Hooki") {
                    Button("Skonfiguruj…") { openWindow(id: HookSetupView.windowID) }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .containerBackground(.ultraThinMaterial, for: .window)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            screens = NSScreen.screens.map(\.localizedName)
            if !settings.screenName.isEmpty, !screens.contains(settings.screenName) {
                screens.append(settings.screenName)   // disconnected now — keep the choice visible
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func soundPicker(_ title: String, _ selection: Binding<String>) -> some View {
        HStack {
            Picker(title, selection: selection) {
                ForEach(AppSettings.systemSounds, id: \.self) { Text($0).tag($0) }
            }
            Button {
                NSSound(named: selection.wrappedValue)?.play()
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .help("Odtwórz")
        }
        .disabled(!settings.soundsEnabled)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        guard on != (service.status == .enabled) else { return }
        do {
            if on { try service.register() } else { try service.unregister() }
            loginError = nil
        } catch {
            loginError = "Nie udało się: \(error.localizedDescription)"
            launchAtLogin = service.status == .enabled
        }
    }
}
