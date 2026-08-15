.PHONY: app install release test

app:
	./scripts/build-app.sh

install:
	./scripts/build-app.sh --install

release:
	./scripts/package-release.sh

test:
	swift test
