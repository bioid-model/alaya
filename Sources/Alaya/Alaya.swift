import Foundation

/// Alaya — the storehouse layer of a `bioid`.
///
/// `Alaya` is the long-lived daemon process. It is the substrate that
/// gives the bioid continuity of self: it starts before any sensory
/// pathway opens, outlives every transient cognitive event, and only
/// stops when the host machine stops.
///
/// In the eight-consciousness mapping used across the bioid family of
/// projects, `Alaya` corresponds to **第八阿頼耶識**: the deepest,
/// always-present storehouse from which the more transient layers
/// (manas, vijñāna, citta, the surface language model) are repeatedly
/// instantiated.
///
/// Responsibilities held by `Alaya`:
/// - hosting the deep, persistent memory of the bioid;
/// - wiring the perception (`vijna`), working context (`citta`),
///   self-model (`manas`), and surface language (`llm`) layers
///   together at process start;
/// - keeping the daemon alive across transient cognitive events.
///
/// Other layers are independent packages, brought in as siblings
/// inside the `bioid` umbrella repository.
@main
struct Alaya {
    static func main() async {
        // Layer wiring will live here once the sibling packages
        // (vijna, citta, manas, llm) are linked in.
    }
}
