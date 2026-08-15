BUNDLE_ID = com.nielsvaes.MacMax
APP = build/Mac Max.app

# Quits a running Mac Max, and shrugs when there is not one — two copies of this app
# means two event taps on the same click. Asking pgrep first (the process is the
# bundle executable, MacMax; the AppleScript name is the bundle's, Mac Max) keeps the
# common case free of both an AppleScript error and an Automation permission prompt.
QUIT = pgrep -x MacMax >/dev/null && osascript -e 'quit app "Mac Max"' >/dev/null 2>&1 || true

.PHONY: test build bundle install run clean reset-permission probe

test:
	swift run MacMaxTests

build:
	swift build -c release

bundle: build
	./scripts/bundle.sh

# A running copy has to go first, and not only to unlock the bundle: `open`
# deduplicates by bundle identifier, so with the old build still running it would
# just re-activate that one and you would be testing the binary you replaced.
install: bundle
	$(QUIT)
	rm -rf "/Applications/Mac Max.app"
	cp -R "$(APP)" /Applications/
	open "/Applications/Mac Max.app"

run: bundle
	$(QUIT)
	open "$(APP)"

probe:
	swift run MacMaxProbe $(ARGS)

reset-permission:
	tccutil reset Accessibility $(BUNDLE_ID)

clean:
	rm -rf .build build
