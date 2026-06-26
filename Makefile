
build:
	@./build.sh

release: build
	@git add .
	@git commit -m "Update modules registry" || echo "No changes to commit"
	@git push
