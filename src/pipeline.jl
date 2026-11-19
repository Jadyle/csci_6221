export ConversionResult, ConversionError, TemplateValidationError, convert_taxonomy

struct ConversionResult
    taxonomy::Taxonomy.ParsedTaxonomy
    template::Template.IntermediateTemplate
    ontology::Ontology.OntologyModel
    output_path::String
end

struct ConversionError <: Exception
    stage::Symbol
    cause::Exception
end

function Base.showerror(io::IO, error::ConversionError)
    print(io, "taxonomy-to-ontology conversion failed during ", error.stage, ": ")
    showerror(io, error.cause)
end

struct TemplateValidationError <: Exception
    issues::Vector{Template.ValidationIssue}
end

function Base.showerror(io::IO, error::TemplateValidationError)
    print(io, "intermediate template failed validation:")
    for issue in error.issues
        print(io, "\n- ", issue.path, " [", issue.code, "]: ", issue.message)
    end
end

function _conversion_stage(operation::Function, stage::Symbol)
    try
        return operation()
    catch error
        error isa InterruptException && rethrow()
        error isa ConversionError && rethrow()
        throw(ConversionError(stage, error))
    end
end

"""
    convert_taxonomy(taxonomy_path; llm=nothing, output_path="ontology.owl")

Load and parse taxonomy input, extract and validate an intermediate template,
generate and validate an ontology, then write RDF/XML to `output_path`.
Returns a `ConversionResult` containing the parsed input, template, ontology,
and exported file path. An LLM implementation is required for extraction.
"""
function convert_taxonomy(
    taxonomy_path::AbstractString;
    llm=nothing,
    output_path::AbstractString="ontology.owl",
)
    document = _conversion_stage(:input_loading) do
        Taxonomy.load_taxonomy(taxonomy_path)
    end

    taxonomy = _conversion_stage(:taxonomy_parsing) do
        Taxonomy.parse_taxonomy(document)
    end

    _conversion_stage(:taxonomy_validation) do
        issues = Taxonomy.validate_taxonomy(taxonomy)
        isempty(issues) || throw(Taxonomy.TaxonomyValidationError(issues))
    end

    template = _conversion_stage(:llm_extraction) do
        llm isa LLM.AbstractLLM || throw(ArgumentError(
            "an LLM provider is required; pass an instance implementing LLM.AbstractLLM",
        ))
        prompt = LLM.build_extraction_prompt(taxonomy)
        response = LLM.complete(llm, prompt)
        response isa AbstractString ||
            throw(ArgumentError("LLM complete must return a string response"))
        LLM.parse_template_response(response)
    end

    _conversion_stage(:template_validation) do
        issues = Template.validate(template)
        isempty(issues) || throw(TemplateValidationError(issues))
    end

    ontology = _conversion_stage(:ontology_generation) do
        Ontology.generate_ontology(template)
    end

    _conversion_stage(:ontology_validation) do
        issues = Ontology.validate(ontology)
        isempty(issues) || throw(Ontology.OntologyGenerationError(issues))
    end

    saved_path = _conversion_stage(:owl_serialization) do
        Ontology.save_ontology(ontology, output_path)
    end

    return ConversionResult(taxonomy, template, ontology, saved_path)
end
