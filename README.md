# TaxonomyOntologyConverter

TaxonomyOntologyConverter is a Julia research-software package for transforming
taxonomy documents into OWL ontologies. An LLM can extract concepts and
relationships into a typed intermediate template; Julia validates that template,
builds an LLM-independent ontology model, and serializes the model as RDF/XML
that can be inspected in Protégé.

The package does not include an LLM provider or automatically apply enrichment
suggestions. The bundled runnable example uses a deterministic mock provider so
the basic workflow can be reproduced without credentials or network access.

## Architecture

```text
Taxonomy file
    → load, parse, validate
    → provider-neutral LLM extraction
    → intermediate JSON template
    → template validation
    → deterministic ontology model
    → ontology validation
    → RDF/XML (.owl)
    → Protégé
```

The implementation is divided into nested Julia modules:

- `Taxonomy` loads input files, detects their format, normalizes text, and
  performs input validation.
- `Template` defines the intermediate representation, validation rules, and
  JSON serialization.
- `LLM` defines the provider interface, extraction prompt, mock provider, and
  structured response parsing.
- `Ontology` defines the semantic model, deterministic template conversion,
  model validation, and RDF/XML serialization.
- `Enrichment` offers manual ontology edits and reviewable LLM proposals.
- `Utils` is reserved for shared utilities; logging and configuration helpers
  are not implemented yet.

## Installation

Use Julia 1.11 or newer. From a checkout of this repository, instantiate the
project environment:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

Then load the package from the repository root:

```sh
julia --project=.
```

```julia
using TaxonomyOntologyConverter
```

RDF.jl is currently unregistered and is pinned to a reviewed git revision in
`Project.toml`. The package does not install or configure an LLM provider.

## Taxonomy input format

`convert_taxonomy(path; ...)` accepts a path to a non-empty text file.
The loader recognizes `.json`, `.csv`, `.html`/`.htm`, `.md`/`.markdown`,
`.xml`, and `.txt` extensions. Unknown extensions are treated as text.

At present, parsing normalizes line endings and checks JSON syntax for `.json`
files. It does not interpret CSV columns, XML elements, HTML, or Markdown into a
taxonomy structure. Those documents are passed as text to the configured LLM
for extraction. The LLM provider is responsible for handling input size limits
and any provider-specific document processing.

The bundled text example is an indented hierarchy:

```text
Artificial intelligence
  Machine learning
    Deep learning
```

See [`data/input/example-taxonomy.txt`](./data/input/example-taxonomy.txt).

## Intermediate template

The intermediate representation keeps extraction independent of both a
particular LLM and OWL serialization. It contains:

- Concepts/classes with IDs, optional names and descriptions, labels, optional
  parent IDs, and metadata.
- Object relationships with IDs, names, source and target concept IDs,
  descriptions, and metadata.
- Data properties with IDs, names, value types, optional concept domains,
  descriptions, and metadata.
- Template schema version and metadata, including an optional ontology IRI.

Incomplete fields can be represented during extraction; `Template.validate`
reports missing required fields, duplicate IDs, invalid references, and
hierarchy cycles. `Template.from_json`/`to_json` and `from_dict`/`to_dict`
support JSON interchange. The bundled example is
[`data/intermediate/example-template.json`](./data/intermediate/example-template.json).

```julia
using TaxonomyOntologyConverter
const Template = TaxonomyOntologyConverter.Template

template = Template.from_json(read("data/intermediate/example-template.json", String))
issues = Template.validate(template)
isempty(issues) || error(issues)
```

## LLM extraction

The LLM is asked for the intermediate JSON template, not OWL. Julia parses and
validates the response before the pipeline continues. The provider-neutral
interface is `TaxonomyOntologyConverter.LLM.AbstractLLM`; a provider implements
`TaxonomyOntologyConverter.LLM.complete(llm, prompt)` and returns response
text. No API key is embedded in the package. Provider credentials should be
read from environment variables or the provider's recommended configuration
mechanism.

`LLM.MockLLM` is included for tests and offline examples. It returns a supplied
response verbatim; it does not perform extraction itself.

## Ontology generation

`Ontology.generate_ontology(template)` maps a validated template to the
in-memory ontology model without an LLM call. Concepts become classes and
parent IDs become subclass axioms. Object relationships become object
properties with source and target domains/ranges; data properties map to
datatype properties. Labels, definitions, and metadata are retained as
annotations where applicable. Generation processes entities deterministically
and validates the resulting model.

The ontology model can also represent individuals, relationship assertions,
annotations, and class restrictions for later enrichment.

## OWL output

`Ontology.save_ontology(ontology, path)` validates the model and writes RDF/XML
to the requested path. RDF.jl constructs the RDF graph, and EzXML writes the
RDF/XML document. The output includes available ontology metadata, classes,
subclass axioms, properties, individuals, annotations, and restrictions.

When entities use local identifiers (for example `deep-learning`), provide an
absolute ontology IRI in template metadata, such as
`"iri": "https://example.org/my-ontology"`. Local IDs are resolved against
that base; absolute entity IRIs can be used without a base IRI.

## Protégé usage

1. Run the example or your own conversion and note the generated `.owl` path.
2. Open Protégé.
3. Use **File → Open** and select the `.owl` file.
4. Inspect the ontology hierarchy, entities, annotations, and axioms.

RDF/XML is used so the generated file can be opened directly in Protégé.

## Ontology enrichment

Manual enrichment and LLM-assisted enrichment operate on the same
`OntologyModel`. LLM enrichment only returns structured suggestions; it never
mutates the ontology. Review proposals, explicitly accept selected suggestion
IDs, validate the result, and then export the updated ontology.

```julia
const Enrichment = TaxonomyOntologyConverter.Enrichment
const Ontology = TaxonomyOntologyConverter.Ontology
const Template = TaxonomyOntologyConverter.Template

template = Template.from_json(read("data/intermediate/example-template.json", String))
ontology = Ontology.generate_ontology(template)
Enrichment.add_class!(
    ontology,
    "Mammal";
    parent="species",
    definition="A warm-blooded vertebrate.",
)
Enrichment.add_object_property!(
    ontology,
    "lives-in";
    domains=["Mammal"],
    ranges=["habitat"],
)
Enrichment.add_restriction!(
    ontology,
    "Mammal",
    "lives-in";
    kind=:some_values_from,
    value="habitat",
)
Ontology.save_ontology(ontology, "data/output/enriched.owl")
```

For LLM proposals, call `Enrichment.propose_enrichment(llm, ontology, dataset)`,
inspect `proposal.suggestions`, then call
`Enrichment.apply_suggestions!(ontology, proposal, accepted_ids)` with only the
IDs approved by the user. Rejected or unreviewed suggestions are not applied.

## Examples

From the repository root, run the complete local workflow:

```sh
julia --project=. examples/basic_conversion.jl
```

The example pairs the bundled taxonomy with a matching canned JSON extraction
in [`examples/mock-extraction.json`](./examples/mock-extraction.json). It
writes `data/output/example-pipeline.owl`; open that file in Protégé. Replace
`MockLLM` with an implementation of `LLM.AbstractLLM` to connect a real
provider.

## Testing

Run the package test suite from the repository root:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

Or, in the Julia REPL:

```julia
] test
```

Tests cover taxonomy loading/parsing/validation, template creation and
validation, mock LLM extraction, ontology generation and validation, RDF/XML
serialization, enrichment review/application, and end-to-end conversion.
Tests do not require API credentials or network access.

## Project structure

```text
.
├── Project.toml
├── README.md
├── .gitignore
├── examples/
│   ├── basic_conversion.jl
│   └── mock-extraction.json
├── data/
│   ├── input/
│   ├── intermediate/
│   └── output/
├── src/
│   ├── TaxonomyOntologyConverter.jl
│   ├── pipeline.jl
│   ├── taxonomy/
│   ├── template/
│   ├── llm/
│   ├── ontology/
│   ├── enrichment/
│   └── utils/
├── docs/
└── test/
    ├── runtests.jl
    ├── taxonomy/
    ├── template/
    ├── llm/
    ├── ontology/
    ├── enrichment/
    └── pipeline/
```
