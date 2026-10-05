# ZboxExtensionKit

macOS 15+, Swift 6.2+. No third-party dependencies.

- `ZboxExtensionProtocol`: protocol v1 values, messages, framing and native view descriptions, shared by the host and extensions.
- `ZboxExtensionSDK`: an independent stdio client with event cancellation, bounded messages and host request matching.

Use `ExtensionClient.run` with an async event handler. Call `context.show` to render a view and `context.call` to invoke an authorized host API. Never write logs to stdout. A cancelled event must not continue mutating your own state or performing external side effects.

See [author guide](../../docs/authoring/extensions.md), [wire contract](../../docs/contracts/extensions.md) and [Swift example](../../examples/extensions/swift-text/Sources/Main.swift).

The SDK does not embed SwiftUI views, grant OS permissions, install dependencies, sign executables or sandbox extension code.
