# TaxonomyOntologyConverter

TaxonomyOntologyConverter is a Julia package for research into converting
taxonomies into ontologies. It includes a typed, LLM-independent intermediate
template, a provider-neutral extraction pipeline, a semantic in-memory
ontology model, deterministic ontology generation, and RDF/XML serialization
for Protégé.

## Architecture

- `Taxonomy` — taxonomy loading, parsing, and validation.
- `Template` — intermediate-template schema, validation, and serialization.
- `LLM` — structured extraction prompts, provider interface, and template validation.
- `Ontology` — semantic ontology model, deterministic template-to-model
  generation, and RDF/XML serialization.
- `Enrichment` — manual and LLM-assisted ontology enrichment.
- `Utils` — logging and configuration utilities.

Each component is a nested module, for example
`TaxonomyOntologyConverter.Taxonomy`. Taxonomy parsing and OWL
enrichment remain placeholders.

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
and `validate` checks the assembled model. The model is serialized to OWL's RDF mapping as RDF/XML.

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

`Ontology.generate_ontology(template)` performs this mapping after validating
the template, then validates the resulting model. It does not use an LLM and
does not serialize OWL. It processes records in identifier order so equivalent
validated templates produce the same model structure.

```julia
const Ontology = TaxonomyOntologyConverter.Ontology
ontology = Ontology.generate_ontology(template)
ontology.classes["deep-learning"].superclasses
```

### OWL serialization and Protégé

`Ontology.save_ontology(ontology, path)` validates the ontology model and writes
an RDF/XML `.owl` file. RDF.jl is used to construct the RDF graph; EzXML builds
the RDF/XML document because RDF.jl's bundled RDF/XML extension supports
parsing, but not writing. RDF/XML is a standard OWL serialization that can be
opened directly in Protégé.

RDF.jl was selected for its typed RDF graph and triple API; alternatives
evaluated for this project documented Turtle/N-Triples writers rather than an
RDF/XML writer. RDF.jl is currently unregistered, so its reviewed git revision
is pinned in `Project.toml`; this dependency is an adoption risk to reassess
before a production release. The `[sources]` mechanism requires Julia 1.11 or
newer.

Local entity identifiers such as `deep-learning` are resolved against the
ontology IRI from template metadata. An ontology without an IRI can still be
serialized if its entity identifiers are already absolute IRIs; local IDs
without a base IRI are rejected. Common prefixes such as `xsd:`, `rdfs:`, and
`dcterms:` are expanded when used for property and datatype IRIs. Primitive
datatype names such as `number`, `string`, and `boolean` map to XSD datatypes.

From the project root, run the complete example workflow:

```sh
julia --project -e 'using TaxonomyOntologyConverter; T=TaxonomyOntologyConverter.Template; O=TaxonomyOntologyConverter.Ontology; template=T.from_json(read("data/intermediate/example-template.json", String)); ontology=O.generate_ontology(template); O.save_ontology(ontology, "data/output/example.owl")'
```

Then open [`data/output/example.owl`](./data/output/example.owl) in Protégé to
visualize and inspect the generated classes, properties, annotations, and
relationships.

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
