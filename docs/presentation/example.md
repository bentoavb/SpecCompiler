# SPEC: Introducing SpecCompiler

A short overview of SpecCompiler: turning structured Markdown into consistent, reusable engineering outputs.

## SECTION: How SpecCompiler works

1. Read project settings and source documents
2. Parse content into the structured SpecIR database
3. Resolve links, references, and generated content
4. Emit documents through Pandoc and format-specific tooling

## SECTION: One source, multiple outputs

```list-table:tbl-outputs{caption="SpecCompiler output formats"}
> header-rows: 1
> aligns: l,l

* - Format
  - Typical use
* - DOCX / PDF
  - Reports and controlled documents
* - HTML5
  - Searchable documentation sites
* - PPTX
  - Slide presentations
* - Markdown / JSON
  - Reuse and data exchange
```

## SECTION: Extend with models

- Define domain-specific objects, relations, and views
- Add format filters, styles, and postprocessors when needed
- Reuse a model across projects for consistent output

## SECTION: SpecCompiler component flow

```puml:specc-architecture{caption="SpecCompiler component flow"}
@startuml
left to right direction
skinparam componentStyle rectangle

component "Markdown\n+ CommonSpec" as Source
component "SpecCompiler\nparse / resolve / emit" as Compiler
database "SpecIR" as IR
component "Pandoc +\nformat tools" as Writers
artifact "DOCX · HTML · PPTX\nMarkdown · JSON" as Outputs

Source --> Compiler : project build
Compiler --> IR : structured content
IR --> Compiler : resolved model data
Compiler --> Writers : render AST
Writers --> Outputs : generated files
@enduml
```