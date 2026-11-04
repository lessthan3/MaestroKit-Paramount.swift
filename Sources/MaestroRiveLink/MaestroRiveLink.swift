// Internal link shim — do not import from consumer code.
// The binary xcframework imports RiveRuntime but can't declare package dependencies;
// this target carries that dependency so it resolves and links into the consuming app.
@_exported import RiveRuntime
