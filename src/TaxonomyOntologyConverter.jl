module TaxonomyOntologyConverter

export hello, Taxonomy, Template, LLM, Ontology, Enrichment, Utils

hello() = "Hello from TaxonomyOntologyConverter!"

module Taxonomy
include("taxonomy/loader.jl")
include("taxonomy/parser.jl")
include("taxonomy/validator.jl")
end

module Template
using JSON

include("template/schema.jl")
include("template/validation.jl")
include("template/serialization.jl")
end

module LLM
using JSON
using ..Template: IntermediateTemplate, ValidationIssue, from_json, validate

include("llm/prompting.jl")
include("llm/extraction.jl")
include("llm/enrichment.jl")
end

module Ontology
include("ontology/model.jl")
include("ontology/classes.jl")
include("ontology/properties.jl")
include("ontology/relationships.jl")
include("ontology/generator.jl")
end

module Enrichment
include("enrichment/manual.jl")
include("enrichment/llm.jl")
end

module Utils
include("utils/logging.jl")
include("utils/configuration.jl")
end

end
