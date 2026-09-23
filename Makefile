SHELL := /usr/bin/env bash

EMACS ?= emacs
EASK ?= eask

.PHONY: clean checkdoc lint install compile test

ci: clean package install compile

clean:
	@echo "Cleaning..."
	$(EASK) clean all

package:
	@echo "Packaging..."
	$(EASK) package

install:
	@echo "Installing..."
	$(EASK) install

compile:
	@echo "Compiling..."
	$(EASK) compile

lint:
	@echo "Linting..."
	$(EASK) lint package

test:
	@echo "Testing..."
	$(EMACS) -Q --batch -L . -l test/test-git-gutter.el -f ert-run-tests-batch-and-exit
