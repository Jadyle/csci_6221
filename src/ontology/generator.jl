export generate_ontology, TemplateValidationError, OntologyGenerationError

struct TemplateValidationError <: Exception
    issues::Vector{Template.ValidationIssue}
end

function Base.showerror(io::IO, error::TemplateValidationError)
    print(io, "cannot generate ontology from an invalid template:")
    for issue in error.issues
        print(io, "\n- ", issue.path, " [", issue.code, "]: ", issue.message)
    end
end

struct OntologyGenerationError <: Exception
    issues::Vector{OntologyValidationIssue}
end

function Base.showerror(io::IO, error::OntologyGenerationError)
    print(io, "generated ontology failed validation:")
    for issue in error.issues
        print(io, "\n- ", issue.path, " [", issue.code, "]: ", issue.message)
    end
end

function _metadata_text(metadata, key::String)
    value = get(metadata, key, nothing)
    isnothing(value) && return nothing
    value isa AbstractString ||
        throw(ArgumentError("template metadata '$key' must be a string"))
    return String(value)
end

function _metadata_texts(metadata, plural_key::String, singular_key::String)
    if haskey(metadata, plural_key)
        value = metadata[plural_key]
        value isa AbstractVector ||
            throw(ArgumentError("template metadata '$plural_key' must be an array of strings"))
        all(item -> item isa AbstractString, value) ||
            throw(ArgumentError("template metadata '$plural_key' must contain only strings"))
        return String[String(item) for item in value]
    elseif haskey(metadata, singular_key)
        value = metadata[singular_key]
        value isa AbstractString ||
            throw(ArgumentError("template metadata '$singular_key' must be a string"))
        return String[String(value)]
    end
    return String[]
end

function _canonical_json_value(value)
    if value isa AbstractDict
        all(key -> key isa AbstractString, keys(value)) ||
            throw(ArgumentError("entity metadata objects must use string keys"))
        entries = [(String(key), item) for (key, item) in pairs(value)]
        sort!(entries; by=first)
        length(unique(first.(entries))) == length(entries) ||
            throw(ArgumentError("entity metadata contains duplicate normalized keys"))
        return Dict{String,Any}(key => _canonical_json_value(item) for (key, item) in entries)
    elseif value isa AbstractVector
        return [_canonical_json_value(item) for item in value]
    end
    return value
end

function _metadata_annotations(metadata)
    annotations = Annotation[]
    for key in sort!(String[String(key) for key in keys(metadata)])
        value = JSON.json(_canonical_json_value(metadata[key]))
        push!(annotations, Annotation("urn:taxonomy-ontology-converter:metadata:$key", value))
    end
    return annotations
end

function _concept_labels(concept::Template.Concept)
    labels = copy(concept.labels)
    if !isnothing(concept.name) && !(concept.name in labels)
        pushfirst!(labels, concept.name)
    end
    return labels
end

function _concept_definitions(concept::Template.Concept)
    return isnothing(concept.description) ? String[] : [concept.description]
end

function _named_labels(name)
    return isnothing(name) ? String[] : [name]
end

function _descriptions(description)
    return isnothing(description) ? String[] : [description]
end

"""
    generate_ontology(template::Template.IntermediateTemplate)

Convert a validated intermediate template into an internal ontology model. This
function performs no LLM calls and does not serialize OWL.
"""
function generate_ontology(template::Template.IntermediateTemplate)
    template_issues = Template.validate(template)
    isempty(template_issues) || throw(TemplateValidationError(template_issues))

    ontology = OntologyModel(
        iri=_metadata_text(template.metadata, "iri"),
        version=_metadata_text(template.metadata, "version"),
        labels=_metadata_texts(template.metadata, "labels", "label"),
        definitions=_metadata_texts(template.metadata, "definitions", "definition"),
        metadata=deepcopy(template.metadata),
    )

    for concept in sort(template.concepts; by=concept -> concept.id)
        add_class!(
            ontology,
            concept.id;
            labels=_concept_labels(concept),
            definitions=_concept_definitions(concept),
            annotations=_metadata_annotations(concept.metadata),
        )
    end

    for concept in sort(template.concepts; by=concept -> concept.id)
        isnothing(concept.parent) && continue
        add_subclass!(ontology, concept.id, concept.parent)
    end

    for relationship in sort(template.relationships; by=relationship -> relationship.id)
        add_object_property!(
            ontology,
            relationship.id;
            labels=_named_labels(relationship.name),
            definitions=_descriptions(relationship.description),
            domains=[relationship.source],
            ranges=[relationship.target],
            annotations=_metadata_annotations(relationship.metadata),
        )
    end

    for property in sort(template.properties; by=property -> property.id)
        domains = isnothing(property.domain) ? String[] : [property.domain]
        ranges = isnothing(property.value_type) ? String[] : [property.value_type]
        add_data_property!(
            ontology,
            property.id;
            labels=_named_labels(property.name),
            definitions=_descriptions(property.description),
            domains=domains,
            ranges=ranges,
            annotations=_metadata_annotations(property.metadata),
        )
    end

    ontology_issues = validate(ontology)
    isempty(ontology_issues) || throw(OntologyGenerationError(ontology_issues))
    return ontology
end
