# TaxonomyOntologyConverter

TaxonomyOntologyConverter is a Julia package for research into converting
taxonomies into ontologies. It includes a typed, LLM-independent intermediate
template for extracted concepts, relationships, and data properties. Ontology
generation and taxonomy extraction are not implemented yet.

## Architecture

- `Taxonomy` — taxonomy loading, parsing, and validation.
- `Template` — intermediate-template schema, validation, and serialization.
- `LLM` — prompting, information extraction, and LLM-assisted enrichment.
- `Ontology` — ontology model, generation, classes, properties, and relationships.
- `Enrichment` — manual and LLM-assisted ontology enrichment.
- `Utils` — logging and configuration utilities.

Each component is a nested module, for example
`TaxonomyOntologyConverter.Taxonomy`. The corresponding source files are
placeholders for future implementations except for the `Template` module.

### Intermediate template

The central data model is in `TaxonomyOntologyConverter.Template`:

- `Concept` stores an identifier, optional name and description, labels, an
  optional parent identifier, and metadata.
- `ObjectRelationship` stores an identifier, optional name, source and target
  concept identifiers, description, and metadata.
- `DataProperty` stores an identifier, optional name and value type, optional
  description and concept domain, and metadata.
- `IntermediateTemplate` groups these records with a schema version and
  template-level metadata.

Optional extracted fields are represented as `Union{Nothing,String}` or empty
collections. Constructors preserve incomplete records; `validate` returns
structured issues for missing required values, duplicate identifiers, invalid
references, and parent cycles. JSON support is provided by `to_json`,
`from_json`, `to_dict`, and `from_dict`. The example at
[`data/intermediate/example-template.json`](./data/intermediate/example-template.json)
shows the serialized shape.

```julia
using TaxonomyOntologyConverter
const Template = TaxonomyOntologyConverter.Template

data = read("data/intermediate/example-template.json", String)
template = Template.from_json(data)
issues = Template.validate(template)
```

## Run the tests

From the package root, start Julia and run:

```julia
] test
```

Alternatively, run the tests without entering the package manager:

```sh
julia --project -e 'using Pkg; Pkg.test()'
```

## Load the package

From the package root, start Julia with the project environment:

```sh
julia --project
```

Then load and try the package:

```julia
using TaxonomyOntologyConverter
hello()
```
