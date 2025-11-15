.PHONY: test test-unit test-integration test-e2e

TEST_RUNNER=./tests/run-tests.sh

test: test-unit test-integration test-e2e

test-unit:
	$(TEST_RUNNER) unit

test-integration:
	$(TEST_RUNNER) integration

test-e2e:
	$(TEST_RUNNER) e2e
