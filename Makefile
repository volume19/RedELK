.PHONY: test test-fast test-integration test-e2e test-nfr

PYTEST ?= python3 -m pytest

test-fast:
	$(PYTEST) -m "unit"

test-integration:
	$(PYTEST) -m "unit or integration or security"

test-e2e:
	$(PYTEST) -m "e2e"

test-nfr:
	$(PYTEST) -m "nfr"

test:
	$(PYTEST)
