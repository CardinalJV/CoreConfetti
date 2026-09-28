//
//  ConfettiOptionsSheet.swift
//  CoreConfetti
//

import SwiftUI
import CoreConfetti

/// The settings sheet: count, colours, symbols. Edits land on the shared
/// `ConfettiOptions` straight away, so the next shot uses them — there is
/// nothing to confirm.
struct ConfettiOptionsSheet: View {

    @Bindable var options: ConfettiOptions
    @Environment(\.dismiss) private var dismiss

    private let symbolColumns = [GridItem(.adaptive(minimum: 56), spacing: 12)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $options.count, in: 1...200) {
                        HStack {
                            Text("Confetti per burst")
                            Spacer()
                            Text("\(options.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Slider(value: countAsDouble, in: 1...200, step: 1)
                        .tint(.purple)

                    Stepper(value: $options.shots, in: 1...10) {
                        HStack {
                            Text("Bursts")
                            Spacer()
                            Text("\(options.shots)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Amount")
                } footer: {
                    Text("One tap fires \(options.shots) burst\(options.shots == 1 ? "" : "s") of \(options.count) confetti.")
                }

                Section {
                    ForEach(ConfettiOptions.palette, id: \.name) { entry in
                        Button {
                            toggleColor(entry.name)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(entry.color)
                                    .frame(width: 22, height: 22)
                                Text(entry.name)
                                Spacer()
                                if options.colorNames.contains(entry.name) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Colors")
                } footer: {
                    Text("At least one color stays selected.")
                }

                Section {
                    LazyVGrid(columns: symbolColumns, spacing: 12) {
                        ForEach(ConfettiOptions.symbolChoices, id: \.self) { name in
                            symbolCell(name)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Symbols")
                } footer: {
                    Text(options.symbolNames.isEmpty
                         ? "No symbols: the cannon fires paper confetti."
                         : "\(options.symbolNames.count) symbol\(options.symbolNames.count == 1 ? "" : "s") selected.")
                }

                if !selectedSymbols.isEmpty {
                    Section {
                        ForEach(selectedSymbols, id: \.self) { name in
                            symbolColorRow(name)
                        }
                    } header: {
                        Text("Color per Symbol")
                    } footer: {
                        Text("A symbol left on “auto” picks a random color from the palette above.")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func symbolCell(_ name: String) -> some View {
        let isOn = options.symbolNames.contains(name)
        return Button {
            if isOn {
                options.symbolNames.remove(name)
            } else {
                options.symbolNames.insert(name)
            }
        } label: {
            Image(systemName: name)
                .font(.title2)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isOn ? Color.purple : Color.secondary.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    /// The last ticked colour stays ticked, so the cannon always has a palette.
    private func toggleColor(_ name: String) {
        if options.colorNames.contains(name) {
            guard options.colorNames.count > 1 else { return }
            options.colorNames.remove(name)
        } else {
            options.colorNames.insert(name)
        }
    }

    /// One symbol and the palette it draws from: the leading swatch is "auto",
    /// which hands the symbol back to the general colours.
    private func symbolColorRow(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: name)
                .font(.title3)
                .foregroundStyle(color(for: name) ?? .primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    swatch(nil, for: name)
                    ForEach(ConfettiOptions.palette, id: \.name) { entry in
                        swatch(entry.name, for: name)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 4)
    }

    /// `colorName == nil` is the "auto" swatch.
    private func swatch(_ colorName: String?, for symbol: String) -> some View {
        let isOn = options.symbolColorNames[symbol] == colorName
        return Button {
            options.symbolColorNames[symbol] = colorName
        } label: {
            ZStack {
                if let colorName, let color = ConfettiOptions.color(named: colorName) {
                    Circle().fill(color)
                } else {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: ConfettiOptions.palette.map(\.color),
                                center: .center
                            )
                        )
                }
                Circle()
                    .strokeBorder(Color.primary, lineWidth: isOn ? 3 : 0)
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(colorName ?? "Auto")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    /// The ticked symbols, in the order the grid shows them.
    private var selectedSymbols: [String] {
        ConfettiOptions.symbolChoices.filter { options.symbolNames.contains($0) }
    }

    private func color(for symbol: String) -> Color? {
        options.symbolColorNames[symbol].flatMap(ConfettiOptions.color(named:))
    }

    private var countAsDouble: Binding<Double> {
        Binding(
            get: { Double(options.count) },
            set: { options.count = Int($0) }
        )
    }
}

#Preview {
    ConfettiOptionsSheet(options: ConfettiOptions())
}
