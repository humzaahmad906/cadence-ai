import SwiftUI

/// The flagship node-graph canvas for a workflow (Build mode).
///
/// A dotted-grid canvas with a pan/zoom content layer. Each block renders as a card with a
/// coloured top accent bar, an icon badge, a category tag pill, a title and a subtitle. Ports
/// live on the card's left (inputs, hollow) and right (outputs, filled) edges; output → input
/// connections are drawn as bezier curves.
///
/// Interactions:
/// - Pan: drag empty canvas. Zoom: the bottom-right `－ 100% ＋ | ⤢` cluster.
/// - Move node: drag a card body (translation ÷ zoom → canvas coords); a small threshold keeps a
///   click a select rather than a move.
/// - Connect (click-to-connect): click an output port to start a link (a dashed bezier follows the
///   cursor), then click a target input port to wire it. Click empty canvas to cancel.
/// - Delete edge: hover its midpoint handle and click the ×.
///
/// Styling uses the app design system (`DS`) exclusively.
struct WorkflowCanvasView: View {
    @EnvironmentObject var appState: AppState
    @Binding var workflow: Workflow
    @Binding var selectedBlockId: UUID?
    @State private var outputViewerId: UUID?

    // Pan / zoom of the content layer. screen = pan + canvas * zoom.
    @State private var pan: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var panStart: CGSize?
    @State private var didInitialFit = false

    // Node drag + click-to-connect state.
    @State private var activeNodeDrag: NodeDrag?
    @State private var linkFrom: PendingLink?
    @State private var pendingCursor: CGPoint = .zero

    // Layout metrics (from the design handoff).
    private let nodeWidth: CGFloat = 224
    private let nodeHeight: CGFloat = 96
    private let zoomMin: CGFloat = 0.35
    private let zoomMax: CGFloat = 1.5
    private let screenSpace = "cadenceCanvasScreen"

    private struct NodeDrag { let id: UUID; let origin: CGPoint }
    private struct PendingLink: Equatable { let block: UUID; let port: String }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let positions = effectivePositions()
            ZStack(alignment: .topLeading) {
                gridBackground
                content(positions: positions)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coordinateSpace(.named(screenSpace))
            .clipped()
            .background(TrackpadGestures(pan: $pan, zoom: $zoom, zoomRange: zoomMin...zoomMax))
            .overlay(alignment: .bottomLeading) { hintPill.padding(16) }
            .overlay(alignment: .bottomTrailing) { zoomCluster(size: geo.size).padding(16) }
            .overlay(alignment: .top) { repoStrip.padding(.top, 12) }
            .onAppear { fitIfNeeded(geo.size) }
            .onChange(of: geo.size) { _, newValue in fitIfNeeded(newValue) }
            .sheet(isPresented: Binding(get: { outputViewerId != nil },
                                        set: { if !$0 { outputViewerId = nil } })) { outputSheet }
        }
    }

    /// The run state for a block in the active run, if any (drives node status + output viewer).
    private func runState(_ id: UUID) -> BlockRunState? {
        appState.activeRun?.blocks.first(where: { $0.id == id })
    }

    @ViewBuilder private var outputSheet: some View {
        let block = workflow.blocks.first(where: { $0.id == outputViewerId })
        let out = outputViewerId.flatMap { runState($0) }?.output ?? ""
        VStack(alignment: .leading, spacing: DS.space3) {
            HStack {
                Text(block?.title.isEmpty == false ? block!.title : (block?.kind.label ?? "Output")).font(DS.Font.title)
                Spacer()
                Button { outputViewerId = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
            if out.isEmpty {
                Text("No output yet — run the workflow first.").font(DS.Font.body).foregroundStyle(DS.textSecondary)
            } else {
                ScrollView { OutputContent(text: out, prose: true).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
        .padding(DS.space6)
        .frame(width: 560, height: 460)
    }

    // MARK: - Background (dotted grid + pan / deselect / cursor tracking)

    private var gridBackground: some View {
        Canvas { context, size in
            let spacing: CGFloat = 22
            let r: CGFloat = 1.2
            let shading = GraphicsContext.Shading.color(DS.textTertiary.opacity(0.35))
            var y: CGFloat = 0
            while y <= size.height {
                var x: CGFloat = 0
                while x <= size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: shading)
                    x += spacing
                }
                y += spacing
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.contentBG)
        .contentShape(Rectangle())
        .gesture(panGesture)
        .onTapGesture {
            if linkFrom != nil { linkFrom = nil } else { selectedBlockId = nil }
        }
        .onContinuousHover(coordinateSpace: .named(screenSpace)) { phase in
            guard linkFrom != nil else { return }
            if case .active(let location) = phase {
                pendingCursor = CGPoint(x: (location.x - pan.width) / zoom,
                                        y: (location.y - pan.height) / zoom)
            }
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(screenSpace))
            .onChanged { value in
                let base = panStart ?? pan
                if panStart == nil { panStart = base }
                pan = CGSize(width: base.width + value.translation.width,
                             height: base.height + value.translation.height)
            }
            .onEnded { _ in panStart = nil }
    }

    // MARK: - Content layer (edges, nodes, ports) under pan/zoom

    private func content(positions: [UUID: CGPoint]) -> some View {
        ZStack(alignment: .topLeading) {
            edgesLayer(positions)
            pendingLayer(positions)
            nodesLayer(positions)
            handlesLayer(positions)
            portsLayer(positions)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scaleEffect(zoom, anchor: .topLeading)
        .offset(x: pan.width, y: pan.height)
    }

    private func edgesLayer(_ positions: [UUID: CGPoint]) -> some View {
        ForEach(workflow.edges) { edge in
            if let s = portPoint(edge.from, edge.fromPort, isInput: false, positions: positions),
               let d = portPoint(edge.to, edge.toPort, isInput: true, positions: positions) {
                EdgeShape(from: s, to: d)
                    .stroke(DS.accent.opacity(0.3),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func pendingLayer(_ positions: [UUID: CGPoint]) -> some View {
        if let lf = linkFrom,
           let s = portPoint(lf.block, lf.port, isInput: false, positions: positions) {
            EdgeShape(from: s, to: pendingCursor)
                .stroke(DS.accent.opacity(0.7),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 5]))
                .allowsHitTesting(false)
        }
    }

    private func nodesLayer(_ positions: [UUID: CGPoint]) -> some View {
        ForEach(Array(workflow.blocks.enumerated()), id: \.element.id) { _, block in
            let tl = positions[block.id] ?? .zero
            let rs = runState(block.id)
            NodeCard(block: block, selected: selectedBlockId == block.id, status: rs?.status)
                .position(x: tl.x + nodeWidth / 2, y: tl.y + nodeHeight / 2)
                .zIndex(selectedBlockId == block.id ? 1 : 0)
                .onTapGesture { selectedBlockId = block.id }
                .gesture(nodeGesture(block: block, origin: tl))
                .contextMenu {
                    Button { selectedBlockId = block.id } label: { Label("Configure", systemImage: "slider.horizontal.3") }
                    Button { outputViewerId = block.id } label: { Label("View output", systemImage: "text.viewfinder") }
                        .disabled((rs?.output ?? "").isEmpty)
                    if rs != nil {
                        Button { Task { await appState.rerunBlock(block.id) } } label: {
                            Label("Re-run from here", systemImage: "arrow.clockwise")
                        }
                    }
                }
        }
    }

    private func handlesLayer(_ positions: [UUID: CGPoint]) -> some View {
        ForEach(workflow.edges) { edge in
            if let s = portPoint(edge.from, edge.fromPort, isInput: false, positions: positions),
               let d = portPoint(edge.to, edge.toPort, isInput: true, positions: positions) {
                EdgeHandle { deleteEdge(edge.id) }
                    .position(x: (s.x + d.x) / 2, y: (s.y + d.y) / 2)
            }
        }
    }

    private func portsLayer(_ positions: [UUID: CGPoint]) -> some View {
        ForEach(Array(workflow.blocks.enumerated()), id: \.element.id) { _, block in
            let accent = block.kind.accent
            ForEach(Array(block.inputPorts.enumerated()), id: \.offset) { _, name in
                if let p = portPoint(block.id, name, isInput: true, positions: positions) {
                    portView(isOutput: false, accent: accent,
                             label: block.inputPorts.count > 1 ? name : nil, at: p) {
                        completeLink(to: block.id, port: name)
                    }
                }
            }
            ForEach(Array(block.outputPorts.enumerated()), id: \.offset) { _, name in
                if let p = portPoint(block.id, name, isInput: false, positions: positions) {
                    portView(isOutput: true, accent: accent,
                             label: block.outputPorts.count > 1 ? name : nil, at: p) {
                        startLink(from: block.id, port: name)
                    }
                }
            }
        }
    }

    private func portView(isOutput: Bool, accent: Color, label: String?,
                          at p: CGPoint, action: @escaping () -> Void) -> some View {
        ZStack {
            PortDot(isOutput: isOutput, accent: accent)
                .onTapGesture(perform: action)
            if let label {
                Text(label)
                    .font(DS.Font.micro)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize()
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(DS.cardBG.opacity(0.92)))
                    .offset(x: isOutput ? 30 : -30)
                    .allowsHitTesting(false)
            }
        }
        .position(x: p.x, y: p.y)
    }

    // MARK: - Node move gesture

    private func nodeGesture(block: WorkflowBlock, origin: CGPoint) -> some Gesture {
        // minimumDistance 4 so a plain click is NOT captured here — it falls through to the port's
        // tap (click-to-connect) or the node's own tap-to-select. Only a real drag moves the node.
        DragGesture(minimumDistance: 4, coordinateSpace: .named(screenSpace))
            .onChanged { value in
                let base: CGPoint
                if let drag = activeNodeDrag, drag.id == block.id {
                    base = drag.origin
                } else {
                    base = origin
                    activeNodeDrag = NodeDrag(id: block.id, origin: origin)
                    selectedBlockId = block.id
                }
                if let i = workflow.blocks.firstIndex(where: { $0.id == block.id }) {
                    workflow.blocks[i].config.x = Double(base.x + value.translation.width / zoom)
                    workflow.blocks[i].config.y = Double(base.y + value.translation.height / zoom)
                }
            }
            .onEnded { _ in activeNodeDrag = nil }
    }

    // MARK: - Connect / disconnect

    private func startLink(from id: UUID, port: String) {
        linkFrom = PendingLink(block: id, port: port)
        if let p = portPoint(id, port, isInput: false, positions: effectivePositions()) {
            pendingCursor = p
        }
    }

    private func completeLink(to id: UUID, port: String) {
        defer { linkFrom = nil }
        guard let lf = linkFrom, lf.block != id else { return }
        let duplicate = workflow.edges.contains {
            $0.from == lf.block && $0.to == id && $0.fromPort == lf.port && $0.toPort == port
        }
        if !duplicate {
            workflow.edges.append(WorkflowEdge(from: lf.block, to: id, fromPort: lf.port, toPort: port))
        }
    }

    private func deleteEdge(_ id: UUID) {
        workflow.edges.removeAll { $0.id == id }
    }

    // MARK: - Geometry

    /// Effective top-left canvas position of every block. Blocks left at (0,0) are auto-laid-out
    /// left-to-right by index so existing workflows render sensibly.
    private func effectivePositions() -> [UUID: CGPoint] {
        var out: [UUID: CGPoint] = [:]
        for (index, block) in workflow.blocks.enumerated() {
            if block.config.x != 0 || block.config.y != 0 {
                out[block.id] = CGPoint(x: block.config.x, y: block.config.y)
            } else {
                out[block.id] = CGPoint(x: 60 + CGFloat(index) * 300, y: 150)
            }
        }
        return out
    }

    /// Canvas-space point of a named port. Empty name resolves to the block's first port; ports are
    /// spaced evenly down the edge (a single port sits at the vertical centre).
    private func portPoint(_ blockId: UUID, _ port: String, isInput: Bool,
                           positions: [UUID: CGPoint]) -> CGPoint? {
        guard let block = workflow.blocks.first(where: { $0.id == blockId }),
              let tl = positions[blockId] else { return nil }
        let ports = isInput ? block.inputPorts : block.outputPorts
        let name = port.isEmpty ? (ports.first ?? "") : port
        let idx = max(0, ports.firstIndex(of: name) ?? 0)
        let y = tl.y + nodeHeight * CGFloat(idx + 1) / CGFloat(ports.count + 1)
        let x = isInput ? tl.x : tl.x + nodeWidth
        return CGPoint(x: x, y: y)
    }

    // MARK: - Zoom / fit

    private func zoomBy(_ delta: CGFloat, size: CGSize) {
        let newZoom = min(zoomMax, max(zoomMin, ((zoom + delta) * 100).rounded() / 100))
        guard abs(newZoom - zoom) > 0.0001 else { return }
        if size.width > 1, size.height > 1 {
            // Keep the viewport centre fixed while zooming.
            let cx = (size.width / 2 - pan.width) / zoom
            let cy = (size.height / 2 - pan.height) / zoom
            pan = CGSize(width: size.width / 2 - cx * newZoom,
                         height: size.height / 2 - cy * newZoom)
        }
        zoom = newZoom
    }

    private func fitIfNeeded(_ size: CGSize) {
        guard !didInitialFit, size.width > 1, size.height > 1, !workflow.blocks.isEmpty else { return }
        fit(in: size, animated: false)
        didInitialFit = true
    }

    /// Centre + scale the node bounding box to fit the viewport (clamped 0.35…1).
    private func fit(in size: CGSize, animated: Bool) {
        let positions = effectivePositions()
        guard size.width > 1, size.height > 1, !positions.isEmpty else { return }
        let xs = positions.values.map(\.x)
        let ys = positions.values.map(\.y)
        let minX = xs.min() ?? 0
        let minY = ys.min() ?? 0
        let maxX = (xs.max() ?? 0) + nodeWidth
        let maxY = (ys.max() ?? 0) + nodeHeight
        let bw = max(1, maxX - minX)
        let bh = max(1, maxY - minY)
        let pad: CGFloat = 60
        var z = min((size.width - pad * 2) / bw, (size.height - pad * 2) / bh, 1)
        z = max(0.35, min(1, z))
        let px = (size.width - bw * z) / 2 - minX * z
        let py = (size.height - bh * z) / 2 - minY * z
        let apply = { self.zoom = z; self.pan = CGSize(width: px, height: py) }
        if animated { withAnimation(.easeInOut(duration: 0.25), apply) } else { apply() }
    }

    // MARK: - Floating controls

    /// Top strip: which repos (and branches) this workflow explores, or a "no repo tagged" warning.
    private var repoStrip: some View {
        HStack(spacing: 6) {
            if workflow.repoIds.isEmpty {
                Label("No repo tagged — agents run unscoped", systemImage: "exclamationmark.triangle.fill")
                    .font(DS.Font.micro).foregroundStyle(DS.warn)
            } else {
                Image(systemName: "folder.fill").font(.caption2).foregroundStyle(DS.accent)
                ForEach(workflow.repoIds, id: \.self) { rid in
                    if let r = appState.repos.first(where: { $0.id == rid }) {
                        let br = workflow.branches[rid] ?? ""
                        HStack(spacing: 3) {
                            Text(r.name).font(DS.Font.micro).foregroundStyle(DS.textPrimary)
                            Image(systemName: "arrow.triangle.branch").font(.system(size: 8)).foregroundStyle(DS.textTertiary)
                            Text(br.isEmpty ? "default" : br).font(DS.Font.mono).foregroundStyle(DS.textSecondary)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(DS.subtleFill))
                    }
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(DS.border, lineWidth: 1))
        .shadow(color: DS.shadowColor, radius: 6, y: 2)
    }

    private var hintPill: some View {
        HStack(spacing: 7) {
            if linkFrom == nil {
                Circle().fill(DS.accent).frame(width: 7, height: 7)
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DS.textTertiary)
                Circle().strokeBorder(DS.accent, lineWidth: 1.5).frame(width: 7, height: 7)
                Text("to connect  ·  drag a node to move")
            } else {
                Circle().strokeBorder(DS.accent, lineWidth: 1.5).frame(width: 7, height: 7)
                Text("Click an input port to connect  ·  click empty space to cancel")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(DS.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).stroke(DS.border, lineWidth: 1))
        .shadow(color: DS.shadowColor, radius: 8, y: 3)
    }

    private func zoomCluster(size: CGSize) -> some View {
        HStack(spacing: 3) {
            controlButton("minus", tint: DS.textSecondary) {
                withAnimation(.easeInOut(duration: 0.18)) { zoomBy(-0.15, size: size) }
            }
            Text("\(Int((zoom * 100).rounded()))%")
                .font(DS.Font.mono)
                .foregroundStyle(DS.textSecondary)
                .frame(width: 42)
            controlButton("plus", tint: DS.textSecondary) {
                withAnimation(.easeInOut(duration: 0.18)) { zoomBy(0.15, size: size) }
            }
            Rectangle().fill(DS.border).frame(width: 1, height: 16).padding(.horizontal, 2)
            controlButton("arrow.up.left.and.arrow.down.right", tint: DS.accent) {
                fit(in: size, animated: true)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).stroke(DS.border, lineWidth: 1))
        .shadow(color: DS.shadowColor, radius: 8, y: 3)
    }

    private func controlButton(_ systemName: String, tint: Color,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Node card

private struct NodeCard: View {
    let block: WorkflowBlock
    let selected: Bool
    var status: BlockRunStatus? = nil

    private var accent: Color { block.kind.accent }

    private var borderColor: Color {
        switch status {
        case .done:           return DS.ok
        case .running:        return DS.accent
        case .failed:         return DS.danger
        case .awaitingReview: return DS.warn
        default:              return selected ? accent : DS.border
        }
    }

    @ViewBuilder private var statusBadge: some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 16))
                .foregroundStyle(DS.ok).background(Circle().fill(.white)).padding(6)
        case .running:
            ProgressView().controlSize(.small).padding(8)
        case .failed:
            Image(systemName: "xmark.octagon.fill").font(.system(size: 16))
                .foregroundStyle(DS.danger).background(Circle().fill(.white)).padding(6)
        case .awaitingReview:
            Image(systemName: "hand.raised.fill").font(.system(size: 14))
                .foregroundStyle(DS.warn).padding(6)
        default:
            EmptyView()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(accent).frame(height: 6)              // top accent bar
            HStack(alignment: .center, spacing: 11) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(accent.opacity(0.14))
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: block.kind.icon)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(accent)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Chip(block.kind.tag, tint: accent)
                    Text(block.title.isEmpty ? block.kind.label : block.title)
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(block.kind.subtitle)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.top, 10)
            .padding(.bottom, 12)
            Spacer(minLength: 0)
        }
        .frame(width: 224, height: 96, alignment: .top)
        .background(DS.cardBG)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous)
                .strokeBorder(borderColor, lineWidth: (status != nil || selected) ? 2 : 1.5)
        )
        .overlay(alignment: .topTrailing) { statusBadge }
        .cardShadow(selected ? 2 : 1)
    }
}

// MARK: - Ports

private struct PortDot: View {
    let isOutput: Bool
    let accent: Color
    @State private var hover = false

    var body: some View {
        dot
            .scaleEffect(hover ? 1.25 : 1)
            .frame(width: 22, height: 22)
            .contentShape(Circle())
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.1), value: hover)
    }

    @ViewBuilder private var dot: some View {
        if isOutput {
            ZStack {
                Circle().fill(Color.white)
                Circle().fill(accent).padding(3)
            }
            .frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(accent.opacity(0.35), lineWidth: 1))
        } else {
            Circle()
                .fill(DS.cardBG)
                .overlay(Circle().strokeBorder(accent, lineWidth: 2))
                .frame(width: 13, height: 13)
        }
    }
}

// MARK: - Edge bezier + delete handle

private struct EdgeShape: Shape {
    var from: CGPoint
    var to: CGPoint

    func path(in _: CGRect) -> Path {
        var path = Path()
        let dx = max(50, abs(to.x - from.x) * 0.5)
        path.move(to: from)
        path.addCurve(to: to,
                      control1: CGPoint(x: from.x + dx, y: from.y),
                      control2: CGPoint(x: to.x - dx, y: to.y))
        return path
    }
}

/// Small delete handle shown at an edge's midpoint; the × reveals on hover.
private struct EdgeHandle: View {
    let onDelete: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(DS.danger))
                .opacity(hover ? 1 : 0)
        }
        .buttonStyle(.plain)
        .frame(width: 26, height: 26)
        .contentShape(Circle())
        .onHover { hover = $0 }
    }
}
