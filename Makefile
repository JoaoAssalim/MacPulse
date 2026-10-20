.PHONY: build app run open install clean

build:
	swift build

app:
	./scripts/build-app.sh release

run:
	swift run

open: app
	open dist/MacPulse.app

install: app
	rm -rf /Applications/MacPulse.app
	cp -R dist/MacPulse.app /Applications/
	@echo "Instalado em /Applications/MacPulse.app"

clean:
	rm -rf .build dist
