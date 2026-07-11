# Express Desired State in typed Go code

Component relationships, platform conditions, and planning rules will be typed Go code, with managed configuration embedded into the binary and exact tool artifacts declared in a checked-in, build-validated `tools.lock.json`. The project will not introduce a user-facing YAML schema, template language, or plugin interface for its single Owner and Desired State, concentrating validation and refactoring in the compiler and tests.
