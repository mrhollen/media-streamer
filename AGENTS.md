## Agent Operating Guide

- Follow Go best practices for language features, concurrency, and error handling.
- Structure the project with idiomatic Go module layout, clear package boundaries, and well-named folders and files.
- Prefer modular, reusable components; keep business logic decoupled from infrastructure.
- Ensure every background or asynchronous task runs inside a dedicated worker component.
- Minimize external dependencies; rely on the standard library when feasible.
- Write thorough automated tests for all changes and ensure the entire test suite passes before completing a task.
