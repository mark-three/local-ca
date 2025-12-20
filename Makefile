SHELL := /bin/bash


# Phony makefile steps to improve makefile linting
.PHONY: all
.PHONY: clean
.PHONY: test


.PHONY: setup-dev-tools
setup-dev-tools:
	pre-commit install
	pre-commit install-hooks
