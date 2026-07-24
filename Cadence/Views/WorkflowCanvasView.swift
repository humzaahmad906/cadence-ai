import SwiftUI

/// Free-form flowchart canvas for a workflow. Shaped nodes (parallelogram = data, rounded rect =
/// process) with named input ports (left) and output ports (right). Drag from an output port to an
/// input port to wire an edge (fan-out / fan-in). Drag a node body to move it. Tap a node to select
/// it (the builder shows its config). Hover an edge to reveal its delete handle.
struct WorkflowCanvasView: View {
    @Binding var workflow: Workflow
    @Binding var selectedBlockId: UUID?

    @State private var dragConn: DragConn?

    private let nodeSize = CGSize(width: 176, height: 60)
    private let rowStride: CGFloat = 120
    private let originX: CGFloat = 140
    private let originY: CGFloat = 70
    private let portR: CGFloat = 5.5
    private let hitRadius: CGFloat = 28
    private let space = "canvas"

    private struct DragConn { let from: UUID; let port: String; var at: CGPoint }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                edgeLayer
                dragLine
                nodeLayer
                portLayer
            }
            .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
            .coordinateSpace(name: space)
            .padding(24)
        }
        .background(DS.contentBG)
    }

    // MARK: edges

    private var edgeLayer: some View {
        ForEach(workflow.edges) { edge in
            if let s = portPoint(edge.from, edge.fromPort, isInput: false),
               let d = portPoint(edge.to, edge.toPort, isInput: true) {
                PortConnector(from: s, to: d)
                    .stroke(DS.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                EdgeHandle(at: CGPoint(x: (s.x + d.x) / 2, y: (s.y + d.y) / 2)) { deleteEdge(edge.id) }
            }
        }
    }

    @ViewBuilder private var dragLine: some View {
        if let dc = dragConn, let s = portPoint(dc.from, dc.port, isInput: false) {
            Path { p in p.move(to: s); p.addLine(to: dc.at) }
                .stroke(DS.accent.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
        }
    }

    // MARK: nodes

    private var nodeLayer: some View {
        let pos = positions()
        return ForEach(Array(workflow.blocks.enumerated()), id: \.element.id) { idx, block in
            NodeView(block: block, selected: selectedBlockId == block.id)
                .frame(width: nodeSize.width, height: nodeSize.height)
                .position(pos[block.id] ?? .zero)
                .onTapGesture { selectedBlockId = block.id }
                .gesture(
                    DragGesture(coordinateSpace: .named(space))
                        .onChanged { g in
                            selectedBlockId = block.id
                            workflow.blocks[idx].config.x = Double(g.location.x)
                            workflow.blocks[idx].config.y = Double(g.location.y)
                        }
                )
        }
    }

    // MARK: ports

    private var portLayer: some View {
        let pos = positions()
        return ForEach(workflow.blocks) { block in
            let r = rect(center: pos[block.id] ?? .zero)
            ForEach(Array(block.inputPorts.enumerated()), id: \.offset) { i, name in
                portDot(at: portOnEdge(r, index: i, count: block.inputPorts.count, left: true),
                        label: block.inputPorts.count > 1 ? name : nil, leftLabel: true,
                        isOutput: false, block: block, port: name)
            }
            ForEach(Array(block.outputPorts.enumerated()), id: \.offset) { i, name in
                portDot(at: portOnEdge(r, index: i, count: block.outputPorts.count, left: false),
                        label: block.outputPorts.count > 1 ? name : nil, leftLabel: false,
                        isOutput: true, block: block, port: name)
            }
        }
    }

    @ViewBuilder
    private func portDot(at pt: CGPoint, label: String?, leftLabel: Bool, isOutput: Bool,
                         block: WorkflowBlock, port: String) -> some View {
        let content = HStack(spacing: 3) {
            if let label, leftLabel { Text(label).font(DS.Font.micro).foregroundStyle(DS.textTertiary) }
            Circle().fill(DS.cardBG).overlay(Circle().stroke(DS.accent, lineWidth: 2))
                .frame(width: portR * 2, height: portR * 2)
            if let label, !leftLabel { Text(label).font(DS.Font.micro).foregroundStyle(DS.textTertiary) }
        }
        .position(pt)

        if isOutput {
            content.gesture(
                DragGesture(coordinateSpace: .named(space))
                    .onChanged { g in dragConn = DragConn(from: block.id, port: port, at: g.location) }
                    .onEnded { g in finishConnection(at: g.location) }
            )
        } else {
            content
        }
    }

    // MARK: connection logic

    private func finishConnection(at point: CGPoint) {
        defer { dragConn = nil }
        guard let dc = dragConn else { return }
        var best: (block: UUID, port: String, dist: CGFloat)?
        let pos = positions()
        for block in workflow.blocks where block.id != dc.from {
            let r = rect(center: pos[block.id] ?? .zero)
            for (i, name) in block.inputPorts.enumerated() {
                let p = portOnEdge(r, index: i, count: block.inputPorts.count, left: true)
                let dist = hypot(p.x - point.x, p.y - point.y)
                if dist < hitRadius, best == nil || dist < best!.dist { best = (block.id, name, dist) }
            }
        }
        guard let target = best else { return }
        let dup = workflow.edges.contains {
            $0.from == dc.from && $0.to == target.block && $0.fromPort == dc.port && $0.toPort == target.port
        }
        if !dup {
            workflow.edges.append(WorkflowEdge(from: dc.from, to: target.block,
                                               fromPort: dc.port, toPort: target.port))
        }
    }

    private func deleteEdge(_ id: UUID) { workflow.edges.removeAll { $0.id == id } }

    // MARK: geometry

    private func positions() -> [UUID: CGPoint] {
        var result: [UUID: CGPoint] = [:]
        for (i, block) in workflow.blocks.enumerated() {
            if block.config.x != 0 || block.config.y != 0 {
                result[block.id] = CGPoint(x: block.config.x, y: block.config.y)
            } else {
                result[block.id] = CGPoint(x: originX + nodeSize.width / 2,
                                           y: originY + nodeSize.height / 2 + CGFloat(i) * rowStride)
            }
        }
        return result
    }

    private func rect(center: CGPoint) -> CGRect {
        CGRect(x: center.x - nodeSize.width / 2, y: center.y - nodeSize.height / 2,
               width: nodeSize.width, height: nodeSize.height)
    }

    private func portOnEdge(_ r: CGRect, index: Int, count: Int, left: Bool) -> CGPoint {
        CGPoint(x: left ? r.minX : r.maxX,
                y: r.minY + CGFloat(index + 1) * r.height / CGFloat(count + 1))
    }

    private func portPoint(_ blockId: UUID, _ port: String, isInput: Bool) -> CGPoint? {
        guard let block = workflow.blocks.first(where: { $0.id == blockId }),
              let center = positions()[blockId] else { return nil }
        let ports = isInput ? block.inputPorts : block.outputPorts
        let name = port.isEmpty ? (ports.first ?? "") : port
        let idx = max(0, ports.firstIndex(of: name) ?? 0)
        return portOnEdge(rect(center: center), index: idx, count: ports.count, left: isInput)
    }

    private var canvasWidth: CGFloat { max(900, (positions().values.map(\.x).max() ?? 0) + 340) }
    private var canvasHeight: CGFloat { max(600, (positions().values.map(\.y).max() ?? 0) + 220) }
}

// MARK: - Edge delete handle (reveals on hover)

private struct EdgeHandle: View {
    let at: CGPoint
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(DS.danger)
                .background(Circle().fill(.white).padding(1))
                .opacity(hovering ? 1 : 0.001)
        }
        .buttonStyle(.plain)
        .frame(width: 22, height: 22)
        .contentShape(Circle())
        .onHover { hovering = $0 }
        .position(at)
    }
}

// MARK: - Node

private struct NodeView: View {
    let block: WorkflowBlock
    let selected: Bool

    var body: some View {
        content
            .background(shape.fill(DS.cardBG))
            .overlay(shape.stroke(selected ? DS.accent : DS.accent.opacity(0.55), lineWidth: selected ? 2.5 : 1.5))
            .shadow(color: .black.opacity(selected ? 0.18 : 0.08), radius: selected ? 6 : 3, y: 2)
    }

    private var content: some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: block.kind.icon).font(.caption).foregroundStyle(DS.accent)
                Text(block.title.isEmpty ? block.kind.label : block.title)
                    .font(DS.Font.caption).fontWeight(.medium)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .foregroundStyle(DS.textPrimary)
            }
            Text(block.kind.label).font(DS.Font.micro).foregroundStyle(DS.textTertiary)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shape: some InsettableShape {
        NodeShape(isData: block.kind == .input || block.kind == .viewer || block.kind == .createTickets)
    }
}

/// Rounded rectangle, or a parallelogram for data-shaped blocks.
private struct NodeShape: InsettableShape {
    let isData: Bool
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        guard isData else { return Path(roundedRect: r, cornerRadius: 12) }
        let slant: CGFloat = 16
        var p = Path()
        p.move(to: CGPoint(x: r.minX + slant, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - slant, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> NodeShape { var c = self; c.inset += amount; return c }
}

// MARK: - Connector

/// Orthogonal connector from an output port (right of a node) to an input port (left of another),
/// with an arrowhead entering the target.
private struct PortConnector: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in _: CGRect) -> Path {
        let midX = (from.x + to.x) / 2
        var p = Path()
        p.move(to: from)
        p.addLine(to: CGPoint(x: midX, y: from.y))
        p.addLine(to: CGPoint(x: midX, y: to.y))
        p.addLine(to: to)
        let a: CGFloat = 6
        p.move(to: CGPoint(x: to.x - a, y: to.y - a))
        p.addLine(to: to)
        p.addLine(to: CGPoint(x: to.x - a, y: to.y + a))
        return p
    }
}
