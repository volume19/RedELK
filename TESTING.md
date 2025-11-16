# Testing Strategy

## Test Philosophy
- **Test pyramid**: We adhere to the pyramid model—a broad base of fast unit tests, a thinner middle of integration tests that touch scripts/config, and a sharp peak of E2E runs (bundle creation + smoke validation) that mirror real operator flows.
- **Test doubles**: We prefer hermetic fakes/stubs (e.g., `mock_cli_dir` for curl/docker, `bundle_artifact` fixture) over ad-hoc patching so tests stay deterministic and debuggable.
- **Operational plumbing focus**: RedELK is a SIEM appliance, so our tests validate configuration wiring, routing logic, and CLI orchestration rather than subjective content output.

## Test Data Strategy
- Version-controlled fixtures live under `tests/fixtures/data` (threat feeds, mock beacon data) and remain minimal but representative.
- Fixtures are loaded programmatically via pytest fixtures (`data_dir`, `mock_cli_dir`) so every test bootstraps the required filesystem state before running.
- Temporary directories and `.env` mutations are isolated with fixtures that clean up automatically after each test to guarantee determinism.

## Test Structure
```
tests/
  unit/           # YAML/schema assertions + script syntax smoke tests
  integration/    # Script execution with faked curl/docker and seeded data
  e2e/            # Bundle creation + bundle_self_test execution
  nfr/            # Latency/observability style checks
  rag/            # Logstash + template alignment tests
  agents/         # Beacon-manager orchestration tests
  security/       # Filebeat hardening + deployment guardrails
  fixtures/       # Stable data + helper binaries
```
- All suites run through `pytest` with markers: `unit`, `integration`, `e2e`, `security`, `rag`, `agents`, `nfr`.
- Shared fixtures live in `tests/conftest.py` (command runners, env guards, bundle factory, mock CLI shims).

## Running Tests Locally
| Command | Description |
| --- | --- |
| `make test-fast` | Run only `@pytest.mark.unit` tests (sub-second feedback loop). |
| `make test-integration` | Run unit + integration + security/agent suites (no Docker required thanks to mock binaries). |
| `make test-e2e` | Run bundle creation + self-test to validate release artifacts. |
| `make test-nfr` | Run non-functional checks (bundle self-test latency guardrail). |
| `make test` | Run the entire suite, including RAG/agent/security assertions. |

## CI Integration
- `.github/workflows/tests.yml` runs automatically:
  - **Pull Requests**: `make test-fast` for rapid feedback.
  - **Pushes to `main`**: Full `make test` run (unit + integration + e2e + NFR).
  - **Nightly (06:00 UTC)**: Executes `make test`, `make test-e2e`, and `make test-nfr` for deeper regression coverage.

## Blocked Tests
- None. Every suite runs deterministically with in-repo fixtures and mocks.
