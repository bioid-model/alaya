import Foundation
@_exported import BioidCore

/// Alaya — the storehouse layer of a `bioid`.
///
/// This module is the *library* half of the ALAYA slot. It provides
/// concrete `Substrate` implementations and the BIOID control loop, and
/// it imports only `BioidCore`. It does not import `Vijna`, `Manas`, or
/// `Manovijna`: those names are forbidden inside this target so that
/// ALAYA depends only on the neutral protocols, never on a particular
/// peer layer's identity.
///
/// The composition root — where concrete peer layers are wired
/// together — lives in the sibling `alayad` executable target. That
/// is the only place in the repository where `Vijna` / `Manas` /
/// `Manovijna` appear next to `Alaya`. This is the bootstrap exception:
/// a single file that knows the names of the layers, so every other
/// file does not have to.
public enum Alaya {}
