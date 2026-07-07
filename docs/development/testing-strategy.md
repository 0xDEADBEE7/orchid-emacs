# Testing Strategy

## Rule: no live CLI calls in tests

No test may invoke the orchid CLI binary or make a network request to an LLM.
All CLI interactions must be stubbed at the `orchid-core--execute-internal-sync`
and `orchid-core--execute-internal-async` boundary.

**Why:** live calls create real sessions (visible in the browser), are
non-deterministic, slow, and depend on credentials and network availability.
They cannot satisfy the FIRST properties (Fast, Isolated, Repeatable).

## The two stubs

`orchid-test-helpers.el` provides two mechanisms:

### `orchid-test-with-mocks` macro

Stubs both sync and async execution with a fixed success response. Use this
for tests that only care whether the right CLI arguments were assembled, or
that exercise code paths triggered by a successful result:

```elisp
(orchid-test-with-mocks
  (orchid-core-send "hello" nil)
  (should (member "send" (car orchid-test-mock-cli-calls))))
```

`orchid-test-mock-cli-calls` accumulates every args list passed to the stub
so you can assert on argument ordering and flag presence.

### `orchid-core-test--with-mock-execute` macro (in `orchid-core-test.el`)

Stubs sync execution with a caller-supplied exit code and JSON output. Use
this when the test cares about how the result is interpreted (success vs
failure, error message extraction, data parsing):

```elisp
(orchid-core-test--with-mock-execute 0 "{\"id\":\"new\"}"
  (let ((r (orchid-core-send "hello" nil)))
    (should (plist-get r :success))
    (should (equal "new" (plist-get (plist-get r :data) :id)))))

(orchid-core-test--with-mock-execute 1 "{\"error\":\"persona not found: default\"}"
  (let ((r (orchid-core-send "hello" nil :persona "default")))
    (should-not (plist-get r :success))
    (should (equal "persona not found: default" (plist-get r :error)))))
```

The captured args are available as `captured-args` inside the body.

## What to test

| Concern | Approach |
|---------|----------|
| Argument assembly (`--id`, `--persona`, message last) | `with-mock-execute`, assert on `captured-args` |
| Result interpretation (success/failure, error message) | `with-mock-execute` with specific exit code + JSON |
| Code paths that branch on async result | `orchid-test-with-mocks` |
| Parser logic | Feed raw JSON strings directly to the parser function |
| Buffer/UI state | Create a temp buffer, call the function, assert on buffer content |
| CLI binary availability | Allowed — `orchid-core-cli-available-p` only shells out to `which` |

## Running tests

```
make test     # unit tests only (default)
make check    # same as test; must pass before every commit
```

There is no integration target. If you need to manually verify end-to-end
behaviour, run the CLI directly from a shell outside the test suite.
