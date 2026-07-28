.PHONY: bootstrap run test-python validate analyze test build-linux

bootstrap:
	./scripts/bootstrap_full_project.sh

run:
	./scripts/run_asset_foundry.sh

test-python:
	python3 -m unittest asset_engine.test_policy -v

validate:
	python3 tool/check_project.py

analyze:
	flutter analyze

test:
	flutter test

build-linux:
	flutter build linux --release
