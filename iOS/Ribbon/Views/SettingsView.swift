import FamilyControls
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var pickingDistracting = false
    @State private var selection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var editingCategory: AppCategory?
    @State private var asking: SessionAsk?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Settings") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("Screen Time")
                    if model.authorized {
                        Text("Allowed. Ribbon can show your day and block apps and websites during sessions.")
                            .font(Typeface.row).foregroundStyle(Theme.muted)
                    } else {
                        PermissionCard()
                    }

                    SectionHeader(text: "Categories") {
                        Button { editingCategory = model.newCategory() } label: { Label("New", systemImage: "plus") }
                            .buttonStyle(PillButtonStyle())
                    }
                    Text("Put apps in your own categories. Today and This week show them there instead of in Apple's category, and count them the way you choose.")
                        .font(Typeface.row).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                    ForEach(model.categories) { category in
                        CategoryRow(category: category) { editingCategory = category }
                    }

                    SectionLabel("Distracting apps")
                    Text("These count as distracting, and time in them counts against session reviews and sets off check-ins. iOS tells Ribbon roughly how long, never which app.")
                        .font(Typeface.row).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    PickedApps(selection: Binding(get: { model.distracting }, set: { model.setDistracting($0) })) {
                        selection = model.distracting
                        pickingDistracting = true
                    }
                    .padding(.top, 12)

                    SectionLabel("Check-ins")
                    let hasDistracting = !model.distracting.applicationTokens.isEmpty || !model.distracting.categoryTokens.isEmpty
                    Toggle(isOn: Binding(get: { model.checkIns && hasDistracting }, set: { model.setCheckIns($0) })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Send check-ins").font(Typeface.row)
                            Text(hasDistracting ? "A notification when your distracting apps pass 15, 30, 45 minutes and more in a day."
                                                : "Choose your distracting apps above first. Check-ins come when they pass 15, 30, 45 minutes and more in a day.")
                                .font(Typeface.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.switchOn)
                    .disabled(!hasDistracting)

                    SectionLabel("AI")
                    Text("With an OpenAI API key, the AI writes your session reviews. It's sent each session's task, session type, times, how it ended and the reason you gave. Nothing from Screen Time is sent.")
                        .font(Typeface.row).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    if model.aiOn {
                        HStack {
                            Label("Key saved", systemImage: "checkmark").font(Typeface.row)
                            Spacer()
                            Button("Remove") { model.saveKey(nil) }.buttonStyle(PillButtonStyle(destructive: true))
                        }
                        .padding(.top, 12)
                    } else {
                        HStack(spacing: 8) {
                            SecureField("sk-…", text: $key).fieldStyle()
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button("Save") { model.saveKey(key); key = "" }
                                .buttonStyle(PillButtonStyle(primary: true))
                                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.top, 12)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How it talks to you").font(Typeface.row)
                        PillChoice(selection: Binding(get: { model.tone }, set: { model.setTone($0) }),
                                   options: Tone.allCases.map { ($0, $0.label) })
                        Text(model.tone == .friendly ? "Playful, never mean. For reviews and check-ins." : "Mocks the distraction, holds you to your goal, and swears. For reviews and check-ins.")
                            .font(Typeface.caption).foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 18)

                    SectionLabel("Emergency pass")
                    Text(model.passNote.text).font(Typeface.row).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    Button("End session…") { asking = .pass }
                        .buttonStyle(PillButtonStyle(destructive: true))
                        .disabled(model.active?.isScheduled != true || !model.passNote.available)
                        .padding(.top, 12)

                    SectionLabel("About")
                    Text("Ribbon \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") for iPhone. What Ribbon records is stored on this phone.")
                        .font(Typeface.row).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Theme.page)
        .presentationCornerRadius(28)
        .screenshotScroll()
        .familyActivityPicker(isPresented: $pickingDistracting, selection: $selection)
        .onChange(of: selection) { if selection != model.distracting { model.setDistracting(selection) } }
        .sheet(item: $editingCategory) { CategoryEditor(category: $0) }
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            if let category = model.openCategory { model.openCategory = nil; editingCategory = category }
        }
        .sheet(item: $asking) { ConfirmSessionAction(ask: $0) }
    }
}

/// One of your categories: its color, name, how it counts and how many apps are in it.
private struct CategoryRow: View {
    let category: AppCategory
    let edit: () -> Void

    var body: some View {
        Button(action: edit) {
            TableRow {
                Swatch(color: Theme.series(category.slot), size: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name).font(Typeface.row).foregroundStyle(Theme.ink)
                    Text("\(category.kindLabel) · \(category.appCount == 0 ? "No apps yet" : "\(category.appCount) app\(category.appCount == 1 ? "" : "s")")")
                        .font(Typeface.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Create or edit a category: its name, color, how it counts, and its apps.
struct CategoryEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var category: AppCategory
    @State private var picking = false

    private var isNew: Bool { !model.categories.contains { $0.id == category.id } }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: isNew ? "New category" : "Edit \(category.name)") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FormRow(label: "Name") {
                        TextField("Code", text: $category.name).fieldStyle()
                    }
                    FormRow(label: "Color") {
                        HStack(spacing: 10) {
                            ForEach(1...8, id: \.self) { slot in
                                Button { category.slot = slot } label: {
                                    Circle().fill(Theme.series(slot)).frame(width: 30, height: 30)
                                        .padding(3)
                                        .overlay(Circle().strokeBorder(category.slot == slot ? Theme.ink : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Color \(slot)")
                                .accessibilityAddTraits(category.slot == slot ? .isSelected : [])
                            }
                        }
                    }
                    FormRow(label: "Counts as", detail: "Productive time counts fully toward your productivity score, neutral time half, distracting time not at all.") {
                        PillChoice(selection: $category.kind, options: AppCategory.kinds)
                    }
                    FormRow(label: "Apps", detail: "These show in this category instead of Apple's. An app is in one of your categories at a time.") {
                        PickedApps(selection: $category.apps) { picking = true }
                    }
                }
                .padding(.horizontal, 20)
            }

            HStack(spacing: 8) {
                if !isNew {
                    Button("Delete") { model.delete(category); dismiss() }.buttonStyle(PillButtonStyle(destructive: true))
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(PillButtonStyle())
                Button(isNew ? "Add" : "Save") {
                    category.name = category.name.trimmingCharacters(in: .whitespaces)
                    model.save(category)
                    dismiss()
                }
                .buttonStyle(PillButtonStyle(primary: true))
                .disabled(category.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .background(Theme.page)
        .presentationCornerRadius(28)
        .screenshotScroll()
        .familyActivityPicker(isPresented: $picking, selection: $category.apps)
    }
}
