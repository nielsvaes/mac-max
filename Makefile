BUNDLE_ID = com.nielsvaes.MacMax
APP = build/Mac Max.app

.PHONY: test build bundle install run clean reset-permission probe

test:
	swift run MacMaxTests

build:
	swift build -c release

bundle: build
	./scripts/bundle.sh

install: bundle
	rm -rf "/Applications/Mac Max.app"
	cp -R "$(APP)" /Applications/
	open "/Applications/Mac Max.app"

run: bundle
	open "$(APP)"

probe:
	swift run MacMaxProbe $(ARGS)

reset-permission:
	tccutil reset Accessibility $(BUNDLE_ID)

clean:
	rm -rf .build build
