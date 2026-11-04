// Internal link shim — do not import from consumer code.
// The binary xcframeworks can't declare package dependencies; this target carries
// `Sentry-Dynamic` so the app embeds the `Sentry.framework` MaestroCore loads at runtime.
@_exported import Sentry
