import SwiftUI

/// What counts as productive, what counts as focus, and where each app and site belongs.
struct CategoriesView: View {
    let model: DashboardModel
    @State private var search = ""

    var body: some View {
        let _ = model.categoryVersion
        Page(width: 820) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Categories").font(Typeface.greeting)
                Text("New apps and sites are sorted by AI the first time you use them. Change anything here and your history follows.")
                    .font(Typeface.body).foregroundStyle(Theme.muted)
            }
            if let notice = model.categoryNotice {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text(notice).font(Typeface.row)
                    Spacer()
                    Button { model.categoryNotice = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.muted)
                }
                .padding(12)
                .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 20)
            }
            HStack {
                SectionLabel("Your categories")
                Spacer()
                Button { model.editingCategory = CategoryEditor.blank(usage: model.items) } label: { Label("New category", systemImage: "plus") }
                    .buttonStyle(PillButtonStyle(primary: true))
            }
            TableHeader(columns: [("Category", nil), ("Counts as", 150), ("Focus time", 80), ("", 64)])
            ForEach(Categories.all) { category in
                TableRow {
                    Swatch(color: category.color, size: 10)
                    Image(systemName: category.symbol).font(.system(size: 13)).foregroundStyle(Theme.muted).frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name).font(Typeface.row)
                        if category.isCustom && !category.hint.isEmpty {
                            Text(category.hint).font(Typeface.caption).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Dropdown(selection: model.rules.kind(category.id), options: Productivity.allCases.map { ($0, $0.label) }) { model.setKind($0, for: category) }
                        .frame(width: 150, alignment: .leading)
                    Toggle("", isOn: Binding(get: { model.rules.isFocus(category.id) }, set: { model.setFocus($0, for: category) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).frame(width: 80)
                    Group {
                        if category.isCustom { Button("Edit") { model.editingCategory = category }.buttonStyle(PillButtonStyle()) }
                        else { Color.clear }
                    }
                    .frame(width: 64)
                }
            }
            HStack {
                SectionLabel("Apps and websites", detail: "last 7 days")
                Spacer()
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            let items = model.items.filter { search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) }
            if items.isEmpty {
                Text("Nothing tracked yet.").font(Typeface.body).foregroundStyle(Theme.muted)
            }
            ForEach(items.prefix(150)) { item in
                TableRow(verticalPadding: 7) {
                    ItemIcon(bundle: item.bundle, domain: item.domain, size: 22)
                    Text(item.label).font(Typeface.row).lineLimit(1)
                    Spacer()
                    Text(model.classifier.source(for: item)).font(Typeface.caption).foregroundStyle(Theme.muted)
                    Text(Format.duration(item.seconds)).font(Typeface.row).monospacedDigit().foregroundStyle(Theme.muted)
                        .frame(width: 64, alignment: .trailing)
                    Dropdown(selection: item.category, options: Categories.all.map { ($0.id, $0.name) }) { model.setCategory(item, to: $0) }
                        .frame(width: 180, alignment: .trailing)
                }
            }
        }
    }
}

/// Make or edit one of your own categories. The description tells the AI what to sort into it.
struct CategoryEditor: View {
    let model: DashboardModel
    @State var category: Category
    @State private var sortRecent = true
    @Environment(\.dismiss) private var dismiss

    /// A new category starts with the color of whatever you use least, so it rarely collides with a busy one.
    static func blank(usage: [KnownItem] = []) -> Category {
        var seconds: [Int: Double] = [:]
        for slot in 1...8 { seconds[slot] = 0 }
        for item in usage { if let slot = Categories.by(item.category).slot { seconds[slot, default: 0] += item.seconds } }
        for category in Categories.custom { if let slot = category.slot { seconds[slot, default: 0] += 1_000_000 } }
        let quietest = seconds.min { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key ?? 7
        return Category(id: "custom-" + UUID().uuidString.prefix(8).lowercased(), name: "", symbol: "graduationcap",
                        slot: quietest, kind: .productive, focus: true, hint: "", isCustom: true)
    }

    private var isNew: Bool { !Categories.custom.contains { $0.id == category.id } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "New category" : "Edit \(category.name)").font(Typeface.heading)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.muted).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 14)
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.horizontal, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FormRow(label: "Name") {
                        HStack(spacing: 8) {
                            Image(systemName: category.symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(category.color, in: RoundedRectangle(cornerRadius: 8))
                            TextField("Interview prep", text: $category.name)
                                .textFieldStyle(.plain).font(.system(size: 14))
                                .padding(.horizontal, 10).frame(height: 30)
                                .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    FormRow(label: "What belongs here", detail: "The AI reads this to sort new apps and sites into the category.") {
                        TextField("LeetCode, interview prep sites, system design videos", text: $category.hint, axis: .vertical)
                            .textFieldStyle(.plain).font(.system(size: 13.5)).lineLimit(2...4)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 8))
                    }
                    FormRow(label: "Color", detail: sharingNote) {
                        HStack(spacing: 10) {
                            ForEach(1...8, id: \.self) { slot in
                                Button { category.slot = slot } label: {
                                    Circle().fill(Theme.series(slot)).frame(width: 20, height: 20)
                                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: category.slot == slot ? 2 : 0).padding(-4))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.leading, 4)
                    }
                    FormRow(label: "Icon") {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 10), alignment: .leading, spacing: 6) {
                            ForEach(Categories.symbols, id: \.self) { symbol in
                                Button { category.symbol = symbol } label: {
                                    Image(systemName: symbol).font(.system(size: 13))
                                        .frame(width: 30, height: 30)
                                        .background(category.symbol == symbol ? Theme.bubble : .clear, in: RoundedRectangle(cornerRadius: 8))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    FormRow(label: "Counts as") {
                        Dropdown(selection: category.kind, options: Productivity.allCases.map { ($0, $0.label) }) { category.kind = $0 }
                    }
                    FormRow(label: "Focus time", detail: "Time here can make up focus blocks.") {
                        Toggle("", isOn: $category.focus).toggleStyle(.switch).labelsHidden()
                    }
                    if isNew && model.assistant.enabled {
                        FormRow(label: "Sort your last week", detail: "The AI moves apps and sites that fit this category better than any other.") {
                            Toggle("", isOn: $sortRecent).toggleStyle(.switch).labelsHidden()
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            HStack(spacing: 8) {
                if !isNew {
                    Button("Delete") { model.delete(category); dismiss() }.buttonStyle(PillButtonStyle(destructive: true))
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(PillButtonStyle())
                Button(isNew ? "Add category" : "Save") {
                    category.name = category.name.trimmingCharacters(in: .whitespaces)
                    model.save(category, sortRecent: isNew && sortRecent)
                    dismiss()
                }
                .buttonStyle(PillButtonStyle(primary: true))
                .keyboardShortcut(.defaultAction)
                .disabled(category.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 640, height: 640)
        .background(Theme.page)
    }

    private var sharingNote: String? {
        let sharing = Categories.all.filter { $0.slot == category.slot && $0.id != category.id }.map(\.name)
        return sharing.isEmpty ? nil : "Shares its color with \(sharing.joined(separator: " and ")). Pick one you rarely use."
    }
}
