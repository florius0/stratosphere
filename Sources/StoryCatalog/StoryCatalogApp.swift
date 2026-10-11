import AppKit
import SwiftUI
import UI

@main
struct StoryCatalogApp: App {
  var body: some Scene {
    WindowGroup("Stratosphere · Story Catalog") {
      CatalogView(initialStory: Self.initialStory)
    }
    .defaultSize(width: 1240, height: 820)
    .windowResizability(.contentMinSize)
  }
  private static var initialStory: StoryID {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: "--story"), arguments.indices.contains(index + 1),
      let story = StoryID(rawValue: arguments[index + 1])
    else { return .busyCompact }
    return story
  }
}

private enum AppearanceChoice: String, CaseIterable, Identifiable {
  case system = "System"
  case light = "Light"
  case dark = "Dark"
  var id: String { rawValue }
  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

private struct CatalogView: View {
  @State private var session: CatalogSession
  @State private var panels = NativePanelController()
  @State private var search = ""
  @State private var appearanceChoice = AppearanceChoice.system
  @State private var appearance = ReviewAppearance()
  @State private var slowPlayback = false
  @State private var repeatPlayback = false
  @State private var replayTask: Task<Void, Never>?
  @State private var retryTask: Task<Void, Never>?
  @State private var replaying = false
  @State private var replayStep = 0
  @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
  @Environment(\.accessibilityReduceTransparency) private var systemReducedTransparency

  init(initialStory: StoryID) {
    _session = State(initialValue: CatalogSession(story: initialStory))
  }
  private var effectiveAppearance: ReviewAppearance {
    var result = appearance
    result.reducedMotion = result.reducedMotion || systemReducedMotion
    result.reducedTransparency = result.reducedTransparency || systemReducedTransparency
    result.duration *= slowPlayback ? 4 : 1
    return result
  }
  private var definition: StoryDefinition { StoryDefinition.all.first { $0.id == session.story }! }

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Divider()
      VStack(spacing: 0) {
        header
        Divider()
        canvas
        Divider()
        replayControls
      }.frame(minWidth: 560, maxWidth: .infinity)
      Divider()
      inspector
    }
    .frame(minWidth: 1100, minHeight: 760)
    .preferredColorScheme(appearanceChoice.colorScheme)
    .onDisappear {
      stopReplay()
      retryTask?.cancel()
      panels.close()
    }
    .onChange(of: appearanceChoice) { updatePanels() }
    .onChange(of: appearance.reducedMotion) { updatePanels() }
    .onChange(of: appearance.reducedTransparency) { updatePanels() }
    .onChange(of: appearance.duration) { updatePanels() }
    .onChange(of: appearance.bounce) { updatePanels() }
    .onChange(of: slowPlayback) { updatePanels() }
    .onChange(of: systemReducedMotion) { updatePanels() }
    .onChange(of: systemReducedTransparency) { updatePanels() }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 9) {
        Image(systemName: "circle.hexagongrid.fill").font(.system(size: 22)).foregroundStyle(.blue)
        VStack(alignment: .leading, spacing: 2) {
          Text("Stratosphere").font(.system(size: 15, weight: .semibold))
          Text("Native story catalog").font(.system(size: 11)).foregroundStyle(.secondary)
        }
      }.padding(.top, 8)
      TextField("Search stories", text: $search).textFieldStyle(.roundedBorder)
      Text("STORIES").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(
        .secondary)
      ScrollView {
        VStack(spacing: 5) {
          ForEach(StoryDefinition.matching(search)) { story in
            Button {
              stopReplay()
              retryTask?.cancel()
              panels.close()
              session.select(story.id)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(story.title).font(
                  .system(size: 12, weight: session.story == story.id ? .semibold : .regular)
                )
                .foregroundStyle(session.story == story.id ? Color.accentColor : .primary)
                Text(story.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
              }.frame(maxWidth: .infinity, alignment: .leading).padding(11)
                .background(
                  session.story == story.id ? Color.accentColor.opacity(0.09) : .clear,
                  in: RoundedRectangle(cornerRadius: 9)
                )
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
          }
          if StoryDefinition.matching(search).isEmpty {
            ContentUnavailableView.search(text: search).scaleEffect(0.8)
          }
        }
      }
      Spacer(minLength: 0)
      Label("Synthetic content only", systemImage: "checkmark.shield")
        .font(.system(size: 10)).foregroundStyle(.secondary)
    }.padding(18).frame(width: 242).background(.bar)
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 5) {
        Text(definition.title).font(.system(size: 19, weight: .semibold))
        Text(definition.detail).font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Spacer()
      Text("NATIVE").font(.system(size: 9, weight: .semibold)).tracking(1)
        .foregroundStyle(.secondary).padding(7).background(.quaternary, in: Capsule())
    }.padding(22)
  }

  private var canvas: some View {
    GeometryReader { geometry in
      ZStack(alignment: .topLeading) {
        Color.clear
          .background {
            LinearGradient(
              colors: [
                Color(red: 0.40, green: 0.53, blue: 0.61),
                Color(red: 0.69, green: 0.74, blue: 0.70),
                Color(red: 0.86, green: 0.82, blue: 0.72),
              ], startPoint: .topLeading, endPoint: .bottomTrailing)
          }
          .overlay(alignment: .topLeading) {
            Ellipse().fill(.white.opacity(0.15)).frame(width: 650, height: 750).rotationEffect(
              .degrees(-35)
            ).offset(x: 140, y: 160)
          }
        VStack(alignment: .leading, spacing: 7) {
          Text("Studio").font(.system(size: 25, weight: .medium, design: .rounded))
          Text("A quiet place for your work.").font(.system(size: 12))
        }.foregroundStyle(.white.opacity(0.85)).padding(.leading, session.expanded ? 310 : 120)
          .padding(.top, 45)
        if session.story == .partialFailure {
          VStack(spacing: 18) {
            OperationStatusView(
              status: session.operation, completedSteps: session.completedSteps,
              appearance: effectiveAppearance, retry: retry)
            Text("Nonblocking status · Completed steps stay completed")
              .font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
          }.position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        } else {
          RailView(
            projects: RailPresentation.rows(
              projects: PresentationFixtures.projects, selected: session.selectedWorkspace),
            expanded: Binding(get: { session.expanded }, set: { session.send(.setExpanded($0)) }),
            appearance: effectiveAppearance, focus: { session.send(.focus($0)) },
            hover: { inside in
              guard session.story == .deepPreview else { return }
              canvasPointer(inside: inside, region: .rail)
            }
          )
          .padding(.leading, 20).padding(.top, 22)
          if session.story == .deepPreview {
            if !session.canvasHover.visible {
              Text("Hover over the rail to explore the tree")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                .padding(.leading, 120).padding(.top, 135)
            }
            WorkspacePreview(
              root: PresentationFixtures.deepTree,
              expandedNodes: Binding(
                get: { session.expandedNodes }, set: { session.expandedNodes = $0 }),
              selected: session.selectedWorkspace, appearance: effectiveAppearance,
              focus: { session.send(.focus($0)) },
              hover: { canvasPointer(inside: $0, region: .preview) }
            )
            .padding(.leading, 103).padding(.top, 86)
            .opacity(session.canvasHover.visible ? 1 : 0)
            .allowsHitTesting(session.canvasHover.visible)
            .animation(effectiveAppearance.animation, value: session.canvasHover.visible)
          }
        }
        VStack {
          Spacer()
          HStack {
            Spacer()
            Text("Sample desktop").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
          }
        }.padding(16)
      }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        .clipped()
    }
  }

  private var replayControls: some View {
    HStack(spacing: 13) {
      Button {
        stopReplay()
        retryTask?.cancel()
        session.reset()
      } label: {
        Label("Reset", systemImage: "arrow.counterclockwise")
      }
      Button {
        replaying ? stopReplay() : startReplay()
      } label: {
        Label(replaying ? "Stop" : "Replay", systemImage: replaying ? "stop.fill" : "play.fill")
      }
      .buttonStyle(.borderedProminent)
      Toggle("Repeat", isOn: $repeatPlayback).toggleStyle(.checkbox)
      Toggle("Slow", isOn: $slowPlayback).toggleStyle(.checkbox)
      Spacer()
      Text(replaying ? "Step \(replayStep + 1) of \(session.replayStepCount)" : "Ready to replay")
        .font(.system(size: 10)).foregroundStyle(.secondary)
    }.controlSize(.small).font(.system(size: 11)).padding(16)
  }

  private var inspector: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 17) {
        Text("Review controls").font(.system(size: 13, weight: .semibold))
        Picker("Appearance", selection: $appearanceChoice) {
          ForEach(AppearanceChoice.allCases) { Text($0.rawValue).tag($0) }
        }
        Toggle("Reduced motion", isOn: $appearance.reducedMotion)
        Toggle("Reduced transparency", isOn: $appearance.reducedTransparency)
        Text("System accessibility settings are always respected.").font(.system(size: 10))
          .foregroundStyle(.secondary)
        Divider()
        Text("Motion").font(.system(size: 12, weight: .semibold))
        HStack {
          Text("Duration")
          Spacer()
          Text(appearance.duration.formatted(.number.precision(.fractionLength(2))) + " s")
            .monospacedDigit()
        }.font(.system(size: 10))
        Slider(value: $appearance.duration, in: 0.15...1.2)
        HStack {
          Text("Bounce")
          Spacer()
          Text(appearance.bounce.formatted(.number.precision(.fractionLength(2)))).monospacedDigit()
        }.font(.system(size: 10))
        Slider(value: $appearance.bounce, in: 0...0.35)
        if session.story != .partialFailure {
          Button(session.expanded ? "Use compact rail" : "Expand rail") {
            withAnimation(effectiveAppearance.animation) {
              session.send(.setExpanded(!session.expanded))
            }
          }
        }
        if session.story == .deepPreview {
          Divider()
          Text("Native hover panel").font(.system(size: 12, weight: .semibold))
          Text(
            "Move from the rail into its preview. Leave both to dismiss after 0.45 s. Click outside to dismiss immediately."
          )
          .font(.system(size: 10)).foregroundStyle(.secondary)
          Button(panels.isOpen ? "Close native panels" : "Open native panels") {
            if panels.isOpen {
              panels.close()
            } else {
              panels.open(
                session: session, appearance: effectiveAppearance,
                colorScheme: appearanceChoice.colorScheme)
            }
          }
          Text(
            "Nonactivating panels keep keyboard focus in the current app. Focus clicks only record a request."
          )
          .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        Divider()
        HStack {
          Text("Action log").font(.system(size: 12, weight: .semibold))
          Spacer()
          Text("\(session.actions.count)").foregroundStyle(.secondary)
        }
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            if session.actions.isEmpty {
              Text("No actions requested. Hover and disclosure are passive.").foregroundStyle(
                .secondary)
            }
            ForEach(Array(session.actions.enumerated()), id: \.offset) { entry in
              Text("\(entry.offset + 1). \(entry.element.description)").frame(
                maxWidth: .infinity, alignment: .leading)
            }
          }.font(.system(size: 10))
        }.frame(minHeight: 110)
        Text("Catalog actions are simulated. Shared components do not control the desktop.").font(
          .system(size: 10)
        ).foregroundStyle(.tertiary)
      }.controlSize(.small).padding(20)
    }.frame(width: 246).background(.background)
  }

  private func canvasPointer(inside: Bool, region: PointerRegion) {
    if inside { session.canvasHover.enter(region) } else { session.canvasHover.leave(region) }
    guard !inside else { return }
    let generation = session.canvasHover.generation
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(450))
      session.canvasHover.dismiss(generation: generation)
    }
  }

  private func updatePanels() {
    panels.updateAppearance(effectiveAppearance, colorScheme: appearanceChoice.colorScheme)
  }

  private func retry() {
    session.send(.retry)
    let generation = session.replayGeneration
    retryTask?.cancel()
    retryTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(1200))
      guard !Task.isCancelled, generation == session.replayGeneration else { return }
      session.send(.retrySucceeded)
    }
  }

  private func startReplay() {
    stopReplay()
    replaying = true
    replayTask = Task { @MainActor in
      repeat {
        let generation = session.beginReplay()
        for step in 0..<session.replayStepCount {
          guard !Task.isCancelled else { return }
          replayStep = step
          withAnimation(effectiveAppearance.animation) {
            session.replayStep(step, generation: generation)
          }
          let delay = session.story == .interruptedExpansion ? (step == 2 ? 900 : 120) : 700
          try? await Task.sleep(for: .milliseconds(delay * (slowPlayback ? 4 : 1)))
        }
        if repeatPlayback { try? await Task.sleep(for: .milliseconds(600)) }
      } while repeatPlayback && !Task.isCancelled
      guard !Task.isCancelled else { return }
      replaying = false
    }
  }

  private func stopReplay() {
    replayTask?.cancel()
    replayTask = nil
    replaying = false
  }
}
