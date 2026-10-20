.PHONY: build app package screenshots run open install clean

build:
	swift build

app:
	./scripts/build-app.sh release

package:
	./scripts/package.sh

screenshots:
	./scripts/update-screenshots.sh

run:
	swift run

open: app
	open dist/MacPulse.app

install: app
	rm -rf /Applications/MacPulse.app
	ditto --norsrc --noextattr dist/MacPulse.app /Applications/MacPulse.app
	@echo "Installed to /Applications/MacPulse.app"

clean:
	rm -rf .build dist
