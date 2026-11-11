.DEFAULT_GOAL := help
.PHONY: help quality release release-test

# Preserve command-line input literally, including Make/shell syntax.
ifneq ($(origin bump),undefined)
export RELEASE_BUMP := $(value bump)
endif
unexport bump

help:
	@printf '%s\n' \
		'Available targets:' \
		'  help     Show maintainer commands' \
		'  quality  Run compilation, formatting, Credo and Dialyzer (mix quality)' \
		'  release  Validate and publish GitHub + Hex (bump=SMALL/MINOR/MAJOR; omit to prompt)' \
		'  release-test  Test releases in isolated Git repos with fake publishers'

quality:
	mix quality

release:
	@python3 -B scripts/release.py

release-test:
	python3 -B -m unittest discover -s scripts -p 'test_release.py'
