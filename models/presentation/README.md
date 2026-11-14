# Presentation reference theme

`tools/style_reference.py` edits the colors and fonts in
`styles/default/reference.pptx`. Change the `COLORS` and `FONTS` values in the
script to customize the theme.

From the SpecCompiler repository root, run the tool with the local image:

```sh
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$PWD:/workspace" -w /workspace \
  --entrypoint python3 speccompiler-core:latest \
  models/presentation/tools/style_reference.py \
  models/presentation/styles/default/reference.pptx
```

To apply the updated reference deck in `specc`, rebuild and reinstall the local
SpecCompiler image:

```sh
docker build -t speccompiler-core:latest .
bash scripts/install.sh
```
