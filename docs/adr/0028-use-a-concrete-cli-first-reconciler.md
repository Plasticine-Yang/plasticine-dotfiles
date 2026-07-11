# Use a concrete CLI-first Reconciler

The CLI will call one concrete Reconciler Module through `Plan`, `Apply`, and `Doctor` methods rather than a hypothetical Go interface or public action DSL. Apply internally creates an immutable Plan, presents and authorizes it, then executes that same value; a closed action model and production/test Adapters for filesystem, processes, downloads, time, and platform behavior remain internal seams, concentrating policy without exposing orchestration complexity to command handlers.
