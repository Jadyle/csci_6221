# TaxonomyOntologyConverter

TaxonomyOntologyConverter is a Julia package for research into converting
taxonomies into ontologies. It includes a typed, LLM-independent intermediate
template, a provider-neutral extraction pipeline, and a semantic in-memory
ontology model. OWL generation and serialization are not implemented yet.

## Architecture

- `Taxonomy` — taxonomy loading, parsing, and validation.
- `Template` — intermediate-template schema, validation, and serialization.
- `LLM` — structured extraction prompts, provider interface, and template validation.
- `Ontology` — semantic ontology model for classes, properties, individuals, and relationships.
- `Enrichment` — manual and LLM-assisted ontology enrichment.
- `Utils` — logging and configuration utilities.

Each component is a nested module, for example
`TaxonomyOntologyConverter.Taxonomy`. Taxonomy parsing and ontology
generation/serialization remain placeholders.

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

### LLM extraction

The LLM layer requests JSON for the intermediate template; it does not generate
OWL. Implementations subtype `AbstractLLM` and implement
`TaxonomyOntologyConverter.LLM.complete(llm, prompt)`. Taxonomy types can be
adapted by implementing `TaxonomyOntologyConverter.LLM.taxonomy_text(taxonomy)`.
The included `MockLLM` supports offline tests. Extraction parses the response
and raises an `ExtractionValidationError` if Julia validation finds issues.

```julia
const LLM = TaxonomyOntologyConverter.LLM
mock = LLM.MockLLM(read("data/intermediate/example-template.json", String))
template = LLM.extract_template(mock, "Example taxonomy text")
```

Provider credentials are outside the core package; a real provider should obtain
them from environment variables or an application configuration mechanism. No
API keys or provider-specific dependencies are included.

### Ontology model

`TaxonomyOntologyConverter.Ontology` provides an LLM-independent in-memory
semantic model. `OntologyModel` stores ontology metadata and annotations;
`OntologyClass` stores labels, definitions, and superclass links;
`ObjectProperty` stores class domains/ranges; `DataProperty` stores class
domains and datatype ranges; `OntologyIndividual` stores class types; and
`OntologyRelationship` represents an object-property assertion between
individuals. The `add_*` operations check references as entities are added,
and `validate` checks the assembled model. This model is not an OWL serializer.

The intermediate template maps naturally to this model:

- Each `Template.Concept` becomes an `OntologyClass`; its `parent` becomes an
  `add_subclass!` link.
- Each `Template.ObjectRelationship` becomes an `ObjectProperty` whose domain
  and range are its source and target concepts. It is not an
  `OntologyRelationship`, which represents an assertion between individuals.
- Each `Template.DataProperty` becomes a `DataProperty`, mapping its concept
  domain and value type to the model's domain and datatype range.
- Template metadata can populate ontology metadata; concept/property metadata
  can be represented as annotations or retained as provenance.

No automatic template-to-ontology mapper has been added yet.

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
