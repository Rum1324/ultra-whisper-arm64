# Makefile for UltraWhisper
# Convenient commands for building and installing

.PHONY: help build install clean run test all

help:
	@echo "UltraWhisper Build Commands:"
	@echo "  make build    - Build the release version"
	@echo "  make install  - Copy built app to /Applications"
	@echo "  make all      - Build and install (default)"
	@echo "  make clean    - Clean build artifacts"
	@echo "  make run      - Run the app in debug mode"
	@echo "  make test     - Run Flutter tests"

all: build install

build:
	@echo "Building UltraWhisper (Release)..."
	@flutter build macos --release

install:
	@echo "Installing to /Applications..."
	@./macos/Scripts/copy_to_applications.sh

clean:
	@echo "Cleaning build artifacts..."
	@flutter clean
	@rm -rf build/

run:
	@echo "Running UltraWhisper (Debug)..."
	@flutter run -d macos

test:
	@echo "Running tests..."
	@flutter test

# Quick rebuild and install
quick: build install
	@echo "Quick rebuild complete!"
	@open /Applications/UltraWhisper.app