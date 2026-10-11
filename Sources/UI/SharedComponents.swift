import SwiftUI

public struct ReviewAppearance: Sendable {
  public var reducedMotion = false
  public var reducedTransparency = false
  public var duration = 0.32
  public var bounce = 0.12
  public init() {}
  public var animation: Animation? {
    reducedMotion ? nil : .spring(duration: duration, bounce: bounce)
  }
}

public struct GlassSurface: ViewModifier {
  let reducedTransparency: Bool
  let radius: CGFloat
  public func body(content: Content) -> some View {
    if reducedTransparency {
      content.background(.background, in: RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).stroke(.primary.opacity(0.1)))
    } else {
      content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
    }
  }
}

public struct ProjectIcon: View {
  let project: WorkspacePresentation
  let selected: Bool
  public init(project: WorkspacePresentation, selected: Bool) {
    self.project = project
    self.selected = selected
  }
  public var body: some View {
    Image(systemName: project.symbol)
      .font(.system(size: 20, weight: .medium))
      .foregroundStyle(
        PresentationFixtures.colors[project.colorIndex % PresentationFixtures.colors.count]
      )
      .frame(width: 42, height: 42)
      .background(
        selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.045),
        in: RoundedRectangle(cornerRadius: 12)
      )
      .overlay(alignment: .topTrailing) {
        if project.badge > 0 {
          Text(project.badge > 9 ? "9+" : String(project.badge))
            .font(.system(size: 9, weight: .semibold)).monospacedDigit()
            .foregroundStyle(.white).padding(.horizontal, 4).padding(.vertical, 2)
            .background(.red, in: Capsule()).offset(x: 4, y: -4)
            .accessibilityLabel("\(project.badge) notifications")
        }
      }
  }
}

public enum RailDimensions {
  public static let compactWidth: CGFloat = 66
  public static let fullWidth: CGFloat = 252
  public static let height: CGFloat = 590
}

public struct RailView: View {
  public let projects: [RailProjectPresentation]
  @Binding var expanded: Bool
  public let appearance: ReviewAppearance
  public let focus: (String) -> Void
  public let hover: (Bool) -> Void
  public let sizeChanged: (CGSize) -> Void
  public init(
    projects: [RailProjectPresentation], expanded: Binding<Bool>, appearance: ReviewAppearance,
    focus: @escaping (String) -> Void, hover: @escaping (Bool) -> Void = { _ in },
    sizeChanged: @escaping (CGSize) -> Void = { _ in }
  ) {
    self.projects = projects
    _expanded = expanded
    self.appearance = appearance
    self.focus = focus
    self.hover = hover
    self.sizeChanged = sizeChanged
  }
  public var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "circle.hexagongrid.fill").font(.system(size: 17)).foregroundStyle(
          .secondary)
        if expanded {
          Text("Workspaces").font(.system(size: 12, weight: .semibold))
          Spacer()
        }
      }.frame(height: 28).padding(.horizontal, 12)
      ScrollView {
        VStack(spacing: 7) {
          ForEach(projects) { row in
            let project = row.project
            VStack(alignment: .leading, spacing: 4) {
              Button {
                focus(project.id)
              } label: {
                HStack(spacing: 11) {
                  ProjectIcon(project: project, selected: row.active)
                  if expanded {
                    VStack(alignment: .leading, spacing: 3) {
                      Text(project.name).font(
                        .system(size: 13, weight: row.active ? .semibold : .regular)
                      ).lineLimit(1)
                      Text(
                        row.path.isEmpty
                          ? "\(project.windows.count) windows" : row.path.joined(separator: " / ")
                      ).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                  }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
              }.buttonStyle(.plain).help(project.name)
                .accessibilityLabel(project.name)
                .accessibilityValue(row.active ? "Selected" : "")
              if expanded && !row.windows.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                  ForEach(row.windows, id: \.self) { window in
                    Label(window, systemImage: "macwindow").lineLimit(1)
                  }
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 53).padding(
                  .vertical, 6)
              }
            }
          }
        }.padding(.horizontal, 10).padding(.top, 5).padding(.bottom, 8)
      }.scrollIndicators(.hidden)
      Divider().padding(.horizontal, 12)
      HStack(spacing: 12) {
        Image(systemName: "safari").foregroundStyle(.blue)
        if expanded {
          Image(systemName: "terminal").foregroundStyle(.secondary)
          Image(systemName: "folder.fill").foregroundStyle(.blue)
          Spacer()
        }
      }.font(.system(size: 19)).frame(height: 30).padding(.horizontal, expanded ? 18 : 0)
      Button {
        withAnimation(appearance.animation) { expanded.toggle() }
      } label: {
        HStack {
          Image(systemName: expanded ? "sidebar.left" : "chevron.right")
          if expanded {
            Text("Compact rail")
            Spacer()
          }
        }.font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(9)
      }.buttonStyle(.plain).help(expanded ? "Use compact rail" : "Expand rail")
    }.padding(.vertical, 10)
      .frame(
        width: expanded ? RailDimensions.fullWidth : RailDimensions.compactWidth,
        height: RailDimensions.height
      )
      .modifier(GlassSurface(reducedTransparency: appearance.reducedTransparency, radius: 23))
      .animation(appearance.animation, value: expanded)
      .onHover(perform: hover)
      .onGeometryChange(for: CGSize.self) {
        $0.size
      } action: {
        sizeChanged($0)
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel(expanded ? "Full workspace rail" : "Compact workspace rail")
  }
}

private struct TreeRow: Identifiable {
  let workspace: WorkspacePresentation
  let depth: Int
  var id: String { workspace.id }
}

public struct WorkspacePreview: View {
  public let root: WorkspacePresentation
  @Binding var expandedNodes: Set<String>
  public let selected: String
  public let appearance: ReviewAppearance
  public let focus: (String) -> Void
  public let hover: (Bool) -> Void
  public init(
    root: WorkspacePresentation, expandedNodes: Binding<Set<String>>, selected: String,
    appearance: ReviewAppearance,
    focus: @escaping (String) -> Void, hover: @escaping (Bool) -> Void = { _ in }
  ) {
    self.root = root
    _expandedNodes = expandedNodes
    self.selected = selected
    self.appearance = appearance
    self.focus = focus
    self.hover = hover
  }
  private func rows(_ node: WorkspacePresentation, depth: Int = 0) -> [TreeRow] {
    [TreeRow(workspace: node, depth: depth)]
      + (expandedNodes.contains(node.id)
        ? node.children.flatMap { rows($0, depth: depth + 1) } : [])
  }
  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 9) {
        ProjectIcon(project: root, selected: false).scaleEffect(0.78).frame(width: 34, height: 34)
        VStack(alignment: .leading, spacing: 2) {
          Text(root.name).font(.system(size: 14, weight: .semibold))
          Text("Explore workspaces").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "rectangle.3.group").foregroundStyle(.secondary)
      }.padding(16)
      Divider().padding(.horizontal, 16)
      ScrollView([.vertical, .horizontal]) {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(rows(root)) { row in
            HStack(spacing: 7) {
              if !row.workspace.children.isEmpty {
                Button {
                  if expandedNodes.contains(row.id) {
                    expandedNodes.remove(row.id)
                  } else {
                    expandedNodes.insert(row.id)
                  }
                } label: {
                  Image(
                    systemName: expandedNodes.contains(row.id) ? "chevron.down" : "chevron.right"
                  )
                  .font(.system(size: 9, weight: .semibold)).frame(width: 14, height: 22)
                }.buttonStyle(.plain).help("Expand or collapse \(row.workspace.name)")
              } else {
                Color.clear.frame(width: 14, height: 22)
              }
              Button {
                focus(row.id)
              } label: {
                HStack(spacing: 8) {
                  Image(
                    systemName: row.workspace.children.isEmpty ? "rectangle.on.rectangle" : "folder"
                  ).foregroundStyle(.secondary).frame(width: 16)
                  Text(row.workspace.name).font(.system(size: 12))
                  Spacer(minLength: 8)
                  if !row.workspace.windows.isEmpty {
                    Text("\(row.workspace.windows.count)").font(.system(size: 10)).foregroundStyle(
                      .tertiary)
                  }
                }.padding(.vertical, 6).contentShape(Rectangle())
              }.buttonStyle(.plain)
            }.padding(.leading, CGFloat(row.depth) * 15).padding(.horizontal, 7)
              .background(
                selected == row.id ? Color.accentColor.opacity(0.12) : .clear,
                in: RoundedRectangle(cornerRadius: 7))
            if expandedNodes.contains(row.id) || row.workspace.children.isEmpty {
              ForEach(row.workspace.windows, id: \.self) { window in
                Label(window, systemImage: "macwindow").font(.system(size: 11)).foregroundStyle(
                  .secondary
                )
                .padding(.leading, CGFloat(row.depth) * 15 + 45).padding(.vertical, 5)
              }
            }
          }
        }.frame(minWidth: 310).padding(9)
      }
      Divider().padding(.horizontal, 16)
      Label("Click a workspace to focus it", systemImage: "cursorarrow")
        .font(.system(size: 10)).foregroundStyle(.secondary).padding(13)
    }.frame(width: 350, height: 430)
      .modifier(GlassSurface(reducedTransparency: appearance.reducedTransparency, radius: 21))
      .onHover(perform: hover)
      .accessibilityLabel("Workspace preview")
  }
}

public struct OperationStatusView: View {
  public let status: OperationPresentation
  public let completedSteps: Int
  public let appearance: ReviewAppearance
  public let retry: () -> Void
  public init(
    status: OperationPresentation, completedSteps: Int, appearance: ReviewAppearance,
    retry: @escaping () -> Void
  ) {
    self.status = status
    self.completedSteps = completedSteps
    self.appearance = appearance
    self.retry = retry
  }
  public var body: some View {
    VStack(alignment: .leading, spacing: 17) {
      HStack(spacing: 10) {
        Image(
          systemName: status == .complete ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        )
        .font(.system(size: 24)).foregroundStyle(status == .complete ? .green : .orange)
        VStack(alignment: .leading, spacing: 3) {
          Text(status == .complete ? "Studio closed" : "Studio partly closed").font(
            .system(size: 15, weight: .semibold))
          Text("\(completedSteps) of 3 steps completed").font(.system(size: 11)).foregroundStyle(
            .secondary)
        }
        Spacer()
      }
      Divider()
      step("Browser saved and closed", complete: true)
      step("Terminal saved and closed", complete: true)
      step(
        status == .complete ? "Notes saved and closed" : "Notes kept open",
        complete: status == .complete)
      if status != .complete {
        Text(
          "Notes could not be saved. Its window is still open; your completed work is preserved."
        )
        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(
          horizontal: false, vertical: true)
        HStack {
          Text("You can continue in other workspaces.").font(.system(size: 10)).foregroundStyle(
            .secondary)
          Spacer()
          Button(action: retry) {
            if status == .retrying {
              HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Retrying…")
              }
            } else {
              Text("Retry")
            }
          }.buttonStyle(.borderedProminent).controlSize(.small).disabled(status == .retrying)
        }
      }
    }.padding(22).frame(width: 385)
      .modifier(GlassSurface(reducedTransparency: appearance.reducedTransparency, radius: 22))
  }
  private func step(_ title: String, complete: Bool) -> some View {
    Label(title, systemImage: complete ? "checkmark.circle" : "pause.circle")
      .font(.system(size: 12)).foregroundStyle(complete ? .secondary : .primary)
  }
}

private struct SharedComponentPreviews: PreviewProvider {
  static var previews: some View {
    Group {
      RailView(
        projects: RailPresentation.rows(
          projects: PresentationFixtures.projects, selected: PresentationFixtures.initialSelection),
        expanded: .constant(false), appearance: ReviewAppearance(), focus: { _ in }
      )
      .padding(24).previewDisplayName("Rail / Compact / Busy")
      WorkspacePreview(
        root: PresentationFixtures.deepTree,
        expandedNodes: .constant(PresentationFixtures.initialExpandedNodes),
        selected: PresentationFixtures.initialSelection, appearance: ReviewAppearance(),
        focus: { _ in }
      )
      .padding(24).previewDisplayName("Hover preview / Deep tree")
    }
  }
}
