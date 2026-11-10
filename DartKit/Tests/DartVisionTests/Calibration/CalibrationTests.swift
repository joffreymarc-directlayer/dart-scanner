import Testing

/// Parent of every calibration suite of lot V2 (VISION.md §10.2, groups C and L).
///
/// The calibration tests render and measure 4K stills, for seconds at a time in a debug build. Run side by side,
/// they would hold every thread of the cooperative pool and starve the tests that wait for frames delivered in real
/// time (`ImagingScriptTests`). Serialised under this parent, they hold at most one; their loops also yield.
@Suite(.serialized) struct CalibrationTests {}
