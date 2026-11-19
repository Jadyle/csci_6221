export OntologyModel, Annotation, OntologyValidationIssue, validate, is_valid
export add_annotation!

abstract type AbstractOntologyClass end
abstract type AbstractObjectProperty end
abstract type AbstractDataProperty end
abstract type AbstractOntologyIndividual end
abstract type AbstractOntologyRelationship end

"""
An ontology annotation with an optional language or datatype.
"""
struct Annotation
    property::String
    value::String
    language::Union{Nothing,String}
    datatype::Union{Nothing,String}
end

function Annotation(
    property::AbstractString,
    value::AbstractString;
    language::Union{AbstractString,Nothing}=nothing,
    datatype::Union{AbstractString,Nothing}=nothing,
)
    return Annotation(
        String(property),
        String(value),
        isnothing(language) ? nothing : String(language),
        isnothing(datatype) ? nothing : String(datatype),
    )
end

"""
A finding returned by ontology-model validation.
"""
struct OntologyValidationIssue
    code::Symbol
    path::String
    message::String
end

"""
Mutable in-memory ontology model, independent of any LLM or serialization format.

Entity registries are keyed by identifier. Class/property/individual identifiers
are kept in separate registries to allow OWL-style punning.
"""
mutable struct OntologyModel
    iri::Union{Nothing,String}
    version::Union{Nothing,String}
    labels::Vector{String}
    definitions::Vector{String}
    metadata::Dict{String,Any}
    annotations::Vector{Annotation}
    classes::Dict{String,AbstractOntologyClass}
    object_properties::Dict{String,AbstractObjectProperty}
    data_properties::Dict{String,AbstractDataProperty}
    individuals::Dict{String,AbstractOntologyIndividual}
    relationships::Vector{AbstractOntologyRelationship}
end

function OntologyModel(;
    iri::Union{AbstractString,Nothing}=nothing,
    version::Union{AbstractString,Nothing}=nothing,
    labels=String[],
    definitions=String[],
    metadata::AbstractDict=Dict{String,Any}(),
    annotations=Annotation[],
)
    return OntologyModel(
        isnothing(iri) ? nothing : String(iri),
        isnothing(version) ? nothing : String(version),
        _ontology_strings(labels, "labels"),
        _ontology_strings(definitions, "definitions"),
        Dict{String,Any}(String(key) => value for (key, value) in pairs(metadata)),
        Annotation[annotations...],
        Dict{String,AbstractOntologyClass}(),
        Dict{String,AbstractObjectProperty}(),
        Dict{String,AbstractDataProperty}(),
        Dict{String,AbstractOntologyIndividual}(),
        AbstractOntologyRelationship[],
    )
end

function _ontology_strings(values, field::String)
    result = String[]
    for value in values
        value isa AbstractString ||
            throw(ArgumentError("$field must contain only strings"))
        push!(result, String(value))
    end
    return result
end

function _ontology_string_set(values, field::String)
    return Set(_ontology_strings(values, field))
end

function _require_identifier(identifier::AbstractString, kind::String)
    isempty(strip(identifier)) && throw(ArgumentError("$kind identifier must not be empty"))
    return String(identifier)
end

function _require_annotation(annotation::Annotation)
    isempty(strip(annotation.property)) &&
        throw(ArgumentError("annotation property must not be empty"))
    !isnothing(annotation.language) && isempty(strip(annotation.language)) &&
        throw(ArgumentError("annotation language must not be empty when provided"))
    !isnothing(annotation.datatype) && isempty(strip(annotation.datatype)) &&
        throw(ArgumentError("annotation datatype must not be empty when provided"))
    return annotation
end

function _validate_texts!(issues, path, field, values)
    entries = values isa AbstractSet ? sort!(collect(values)) : values
    for (index, value) in enumerate(entries)
        if isempty(strip(value))
            push!(issues, OntologyValidationIssue(
                :empty_text,
                "$path.$field[$index]",
                "$field entries must not be empty",
            ))
        end
    end
    return issues
end

function _validate_annotations!(issues, path, annotations)
    for (index, annotation) in enumerate(annotations)
        if isempty(strip(annotation.property))
            push!(issues, OntologyValidationIssue(
                :empty_annotation_property,
                "$path.annotations[$index].property",
                "annotation property must not be empty",
            ))
        end
        if !isnothing(annotation.language) && isempty(strip(annotation.language))
            push!(issues, OntologyValidationIssue(
                :empty_annotation_language,
                "$path.annotations[$index].language",
                "annotation language must not be empty when provided",
            ))
        end
        if !isnothing(annotation.datatype) && isempty(strip(annotation.datatype))
            push!(issues, OntologyValidationIssue(
                :empty_annotation_datatype,
                "$path.annotations[$index].datatype",
                "annotation datatype must not be empty when provided",
            ))
        end
    end
    return issues
end

function _validate_identifier!(issues, path, identifier)
    if isempty(strip(identifier))
        push!(issues, OntologyValidationIssue(
            :empty_identifier,
            path,
            "identifier must not be empty",
        ))
    end
    return issues
end

function _validate_class_references!(issues, ontology, path, field, references)
    entries = references isa AbstractSet ? sort!(collect(references)) : references
    for reference in entries
        if !(reference in keys(ontology.classes))
            push!(issues, OntologyValidationIssue(
                :invalid_reference,
                "$path.$field",
                "$field references unknown class '$reference'",
            ))
        end
    end
    return issues
end
