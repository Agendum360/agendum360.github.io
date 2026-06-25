
release:
	@git add .
	@git commit -m "Update modules registry" || echo "No changes to commit"
	@git push
