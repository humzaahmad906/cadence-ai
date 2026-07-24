import SwiftUI

/// SIPOC-style flowchart canvas for a workflow: colored lanes (Suppliers / Inputs / Process /
/// Outputs / Customers), shaped nodes (parallelogram = input/output data, rounded rect = process),
/// and orthogonal blue connectors between wired blocks. Nodes are draggable; dropping a node in a
/// different lane reassigns it. Tapping a node selects it (the builder shows its config inspector).
struct WorkflowCanvasView: View {
    @Binding var workflow: Workflow
    @Binding var selectedBlockId: UUID?

    // Layout metrics
    private let laneWidth: CGFloat = 260
    private let headerH: CGFloat = 46
    private let nodeSize = CGSize(width: 176, height: 60)
    private let rowStride: CGFloat = 104
    private let topPad: CGFloat = 24

    private var lanes: [WorkflowLane] { WorkflowLane.allCases }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                laneBackgrounds
                edgeLayer
                nodeLayer
            }
            .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
            .padding(24)
        }
        .background(DS.contentBG)
    }

    // MARK: lanes

    private var laneBackgrounds: some View {
        ForEach(Array(lanes.enumerated()), id: \.element) { idx, lane in
            let x = CGFloat(idx) * laneWidth
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(laneColor(lane).opacity(0.04))
                    .frame(width: laneWidth, height: canvasHeight)
                Text(lane.label)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: laneWidth, height: headerH)
                    .background(laneColor(lane))
                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(laneColor(lane).opacity(0.4))
                    .frame(width: laneWidth, height: canvasHeight)
            }
            .position(x: x + laneWidth / 2, y: canvasHeight / 2)
        }
    }

    // MARK: edges

    private var edgeLayer: some View {
        let pos = positions()
        return ForEach(effectiveEdges()) { edge in
            if let s = pos[edge.from], let d = pos[edge.to] {
                ElbowConnector(from: rect(center: s), to: rect(center: d))
                    .stroke(DS.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
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
                    DragGesture()
                        .onChanged { g in
                            selectedBlockId = block.id
                            workflow.blocks[idx].config.x = Double(g.location.x)
                            workflow.blocks[idx].config.y = Double(g.location.y)
                        }
                        .onEnded { g in
                            // Snap lane to whichever column the node was dropped in.
                            let laneIdx = max(0, min(lanes.count - 1, Int(g.location.x / laneWidth)))
                            workflow.blocks[idx].config.lane = lanes[laneIdx].rawValue
                        }
                )
        }
    }

    // MARK: layout

    /// Center point for every block: stored (x,y) if set, else auto-placed in its lane column.
    private func positions() -> [UUID: CGPoint] {
        var result: [UUID: CGPoint] = [:]
        var slot: [WorkflowLane: Int] = [:]
        for block in workflow.blocks {
            let lane = laneOf(block)
            if block.config.x != 0 || block.config.y != 0 {
                result[block.id] = CGPoint(x: block.config.x, y: block.config.y)
            } else {
                let s = slot[lane, default: 0]
                slot[lane] = s + 1
                let laneIdx = lanes.firstIndex(of: lane) ?? 2
                let x = CGFloat(laneIdx) * laneWidth + laneWidth / 2
                let y = headerH + topPad + nodeSize.height / 2 + CGFloat(s) * rowStride
                result[block.id] = CGPoint(x: x, y: y)
            }
        }
        return result
    }

    private func laneOf(_ block: WorkflowBlock) -> WorkflowLane {
        WorkflowLane(rawValue: block.config.lane) ?? WorkflowLane.default(for: block.kind)
    }

    /// Explicit edges if any; otherwise a sensible linear chain so existing workflows show connected.
    private func effectiveEdges() -> [WorkflowEdge] {
        if !workflow.edges.isEmpty { return workflow.edges }
        var derived: [WorkflowEdge] = []
        let ids = workflow.blocks.map { $0.id }
        for i in 0..<max(0, ids.count - 1) {
            derived.append(WorkflowEdge(from: ids[i], to: ids[i + 1]))
        }
        return derived
    }

    private func rect(center: CGPoint) -> CGRect {
        CGRect(x: center.x - nodeSize.width / 2, y: center.y - nodeSize.height / 2,
               width: nodeSize.width, height: nodeSize.height)
    }

    private var canvasWidth: CGFloat { CGFloat(lanes.count) * laneWidth }
    private var canvasHeight: CGFloat {
        let maxSlots = Dictionary(grouping: workflow.blocks, by: laneOf).values.map(\.count).max() ?? 1
        let autoH = headerH + topPad + CGFloat(max(1, maxSlots)) * rowStride + 80
        let draggedH = (workflow.blocks.map { $0.config.y }.max() ?? 0) + 160
        return max(700, autoH, draggedH)
    }

    private func laneColor(_ lane: WorkflowLane) -> Color {
        switch lane {
        case .suppliers: return .blue
        case .inputs:    return .green
        case .process:   return .orange
        case .outputs:   return .purple
        case .customers: return .red
        }
    }
}

// MARK: - Node

private struct NodeView: View {
    let block: WorkflowBlock
    let selected: Bool

    var body: some View {
        content
            .overlay(shape.stroke(selected ? DS.accent : DS.accent.opacity(0.55), lineWidth: selected ? 2.5 : 1.5))
            .background(shape.fill(DS.cardBG))
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
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Parallelogram for data (input/output) blocks, rounded rect for everything else.
    private var shape: some InsettableShape {
        NodeShape(isData: block.kind == .input || block.kind == .viewer || block.kind == .createTickets)
    }
}

/// A rounded rectangle, or a parallelogram for data-shaped blocks. Insettable so it can both
/// fill and stroke cleanly.
private struct NodeShape: InsettableShape {
    let isData: Bool
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        guard isData else {
            return Path(roundedRect: r, cornerRadius: 12)
        }
        let slant: CGFloat = 16
        var p = Path()
        p.move(to: CGPoint(x: r.minX + slant, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - slant, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> NodeShape {
        var c = self; c.inset += amount; return c
    }
}

// MARK: - Connector

/// An orthogonal (right-angle) connector between two node rects, with an arrowhead at the target.
/// Exits/enters horizontally when the nodes are mostly side-by-side, vertically otherwise.
private struct ElbowConnector: Shape {
    let from: CGRect
    let to: CGRect

    func path(in _: CGRect) -> Path {
        let dx = to.midX - from.midX
        let dy = to.midY - from.midY
        var start: CGPoint, end: CGPoint, mids: [CGPoint]

        if abs(dx) >= abs(dy) {
            if dx >= 0 {
                start = CGPoint(x: from.maxX, y: from.midY); end = CGPoint(x: to.minX, y: to.midY)
            } else {
                start = CGPoint(x: from.minX, y: from.midY); end = CGPoint(x: to.maxX, y: to.midY)
            }
            let midX = (start.x + end.x) / 2
            mids = [CGPoint(x: midX, y: start.y), CGPoint(x: midX, y: end.y)]
        } else {
            if dy >= 0 {
                start = CGPoint(x: from.midX, y: from.maxY); end = CGPoint(x: to.midX, y: to.minY)
            } else {
                start = CGPoint(x: from.midX, y: from.minY); end = CGPoint(x: to.midX, y: to.maxY)
            }
            let midY = (start.y + end.y) / 2
            mids = [CGPoint(x: start.x, y: midY), CGPoint(x: end.x, y: midY)]
        }

        var p = Path()
        p.move(to: start)
        for m in mids { p.addLine(to: m) }
        p.addLine(to: end)

        // arrowhead
        let entryVertical = abs(mids.last!.x - end.x) < 0.5
        let a: CGFloat = 6
        if entryVertical {
            let dir: CGFloat = end.y >= mids.last!.y ? 1 : -1
            p.move(to: CGPoint(x: end.x - a, y: end.y - a * dir))
            p.addLine(to: end)
            p.addLine(to: CGPoint(x: end.x + a, y: end.y - a * dir))
        } else {
            let dir: CGFloat = end.x >= mids.last!.x ? 1 : -1
            p.move(to: CGPoint(x: end.x - a * dir, y: end.y - a))
            p.addLine(to: end)
            p.addLine(to: CGPoint(x: end.x - a * dir, y: end.y + a))
        }
        return p
    }
}
