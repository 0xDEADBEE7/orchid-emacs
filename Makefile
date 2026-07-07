EMACS ?= emacs
SEEK_PATH = $(shell cd ../.. && pwd)/lisp/seek
BATCH = $(EMACS) --batch -Q -L lisp -L test -L $(SEEK_PATH)

UNIT_TESTS = \
	test/orchid-core-test.el \
	test/orchid-session-test.el \
	test/orchid-session-browser-test.el \
	test/orchid-log-test.el \
	test/orchid-log-restore-test.el \
	test/orchid-log-pipeline-test.el \
	test/orchid-chat-header-test.el \
	test/orchid-chat-session-test.el \
	test/orchid-collapsible-test.el \
	test/orchid-parser-test.el \
	test/orchid-browser-format-test.el \
	test/orchid-chat-send-test.el \
	test/orchid-processing-indicator-test.el \
	test/orchid-chat-display-test.el \
	test/orchid-socket-view-test.el

LISP_SOURCES = \
	$(wildcard lisp/*.el) \
	$(wildcard lisp/core/*.el) \
	$(wildcard lisp/session/*.el) \
	$(wildcard lisp/chat/*.el) \
	$(wildcard lisp/log/*.el) \
	$(wildcard lisp/browser/*.el) \
	$(wildcard lisp/parsers/*.el) \
	orchid.el

.PHONY: help test unit integration check lint clean build

help:
	@echo "Targets:"
	@echo "  build        Byte-compile all Emacs Lisp sources"
	@echo "  test         Run unit tests"
	@echo "  integration  Run integration tests (requires orchid CLI)"
	@echo "  check        Run lint and unit tests"
	@echo "  lint         Run checkdoc linter"
	@echo "  clean        Remove compiled .elc files"

unit:
	$(BATCH) \
		$(foreach f,$(UNIT_TESTS),-l $(f)) \
		-f ert-run-tests-batch-and-exit

integration:
	$(BATCH) \
		-l test/orchid-integration-test.el \
		-f ert-run-tests-batch-and-exit

test: unit

check: lint unit

lint:
	$(BATCH) \
		--eval "(require 'checkdoc)" \
		--eval "(setq checkdoc-spellcheck-documentation-flag nil)" \
		$(foreach f,$(LISP_SOURCES),--eval "(checkdoc-file \"$(f)\")")

build:
	$(BATCH) \
		--eval "(setq byte-compile-error-on-warn t)" \
		-f batch-byte-compile $(LISP_SOURCES)

clean:
	rm -f \
		lisp/*.elc \
		lisp/core/*.elc \
		lisp/session/*.elc \
		lisp/chat/*.elc \
		lisp/log/*.elc \
		lisp/browser/*.elc \
		lisp/parsers/*.elc \
		orchid.elc
