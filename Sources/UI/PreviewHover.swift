import Observation

/// Each review surface owns its hover state so dismissing one cannot clear another.
@MainActor @Observable
public final class PreviewHover {
  public private(set) var visible = false
  public private(set) var generation = 0
  private var regions: Set<PointerRegion> = []
  public init() {}
  public func enter(_ region: PointerRegion) {
    regions.insert(region)
    generation += 1
    visible = true
  }
  public func leave(_ region: PointerRegion) {
    regions.remove(region)
    generation += 1
  }
  public func dismiss(generation: Int) {
    guard generation == self.generation, regions.isEmpty else { return }
    visible = false
  }
  public func close() {
    generation += 1
    regions.removeAll()
    visible = false
  }
}
