import KIndicatorCore
import SwiftUI

/// A keyboard drawn to scale from its layout; click a key to select it. What each key shows,
/// its colour and whether it can be picked come from the caller, so other features can
/// reuse the drawing (a Fn cheat sheet, per-key lighting).
struct KeyboardLayoutView<Label: View>: View {
    let layout: KeyboardLayout
    @Binding var selection: KeyPosition?
    /// Points per key unit (the width of a letter key).
    let unit: CGFloat
    let isEnabled: (LayoutKey) -> Bool
    let fill: (LayoutKey) -> Color?
    let label: (LayoutKey) -> Label

    init(layout: KeyboardLayout, selection: Binding<KeyPosition?>, unit: CGFloat = 28,
         isEnabled: @escaping (LayoutKey) -> Bool = { !$0.isKnob },
         fill: @escaping (LayoutKey) -> Color? = { _ in nil },
         @ViewBuilder label: @escaping (LayoutKey) -> Label) {
        self.layout = layout
        _selection = selection
        self.unit = unit
        self.isEnabled = isEnabled
        self.fill = fill
        self.label = label
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.keys) { key in
                let bounds = key.bounds
                let isSelected = selection == key.position
                Button {
                    selection = key.position
                } label: {
                    KeyCap(key: key, unit: unit, fill: fill(key), isSelected: isSelected, label: label(key))
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled(key))
                .frame(width: bounds.width * unit, height: bounds.height * unit)
                .offset(x: bounds.x * unit, y: bounds.y * unit)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(width: layout.width * unit, height: layout.height * unit, alignment: .topLeading)
    }
}

/// One key: its outline (a circle for the knob), colour and label.
private struct KeyCap<Label: View>: View {
    let key: LayoutKey
    let unit: CGFloat
    let fill: Color?
    let isSelected: Bool
    let label: Label

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = key.isKnob ? AnyShape(Circle().inset(by: unit * 0.12)) : AnyShape(KeyShape(key: key, unit: unit))
        ZStack {
            shape.fill(fill ?? baseColor)
            shape.stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.18), lineWidth: isSelected ? 2 : 0.5)
            label
                .font(.system(size: unit * 0.3, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, unit * 0.08)
                .foregroundStyle(fill == nil ? Color.primary : Color.white)
        }
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(shape)
    }

    private var baseColor: Color {
        switch key.kind {
        case .alpha: Color.primary.opacity(0.06)
        case .modifier: Color.primary.opacity(0.12)
        case .accent: Color.primary.opacity(0.2)
        }
    }
}

/// A key's outline in its own frame: a rounded rectangle, or two merged for ISO Enter.
private struct KeyShape: Shape {
    let key: LayoutKey
    let unit: CGFloat

    func path(in rect: CGRect) -> Path {
        let bounds = key.bounds
        let gap = unit * 0.06
        let radius = unit * 0.14
        func outline(_ part: KeyRect) -> CGPath {
            let frame = CGRect(x: (part.x - bounds.x) * unit, y: (part.y - bounds.y) * unit,
                               width: part.width * unit, height: part.height * unit).insetBy(dx: gap, dy: gap)
            return CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
        guard let second = key.secondRect else { return Path(outline(key.rect)) }
        return Path(outline(key.rect).union(outline(second)))
    }
}
