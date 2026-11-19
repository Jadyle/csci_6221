export Concept, ObjectRelationship, DataProperty, IntermediateTemplate
export ValidationIssue, validate, is_valid, to_dict, from_dict, to_json, from_json

"""
An extracted taxonomy concept. `id` is the stable reference used by the template;
the remaining descriptive fields may be incomplete while extraction is in progress.
"""
struct Concept
    id::String
    name::Union{Nothing,String}
    labels::Vector{String}
    description::Union{Nothing,String}
    parent::Union{Nothing,String}
    metadata::Dict{String,Any}
end

function Concept(
    id::AbstractString;
    name::Union{AbstractString,Nothing}=nothing,
    labels::AbstractVector{<:AbstractString}=String[],
    description::Union{AbstractString,Nothing}=nothing,
    parent::Union{AbstractString,Nothing}=nothing,
    metadata::AbstractDict=Dict{String,Any}(),
)
    return Concept(
        String(id),
        isnothing(name) ? nothing : String(name),
        String[String(label) for label in labels],
        isnothing(description) ? nothing : String(description),
        isnothing(parent) ? nothing : String(parent),
        Dict{String,Any}(String(key) => value for (key, value) in pairs(metadata)),
    )
end

"""
An object relationship between two concepts.
"""
struct ObjectRelationship
    id::String
    name::Union{Nothing,String}
    source::Union{Nothing,String}
    target::Union{Nothing,String}
    description::Union{Nothing,String}
    metadata::Dict{String,Any}
end

function ObjectRelationship(
    id::AbstractString;
    name::Union{AbstractString,Nothing}=nothing,
    source::Union{AbstractString,Nothing}=nothing,
    target::Union{AbstractString,Nothing}=nothing,
    description::Union{AbstractString,Nothing}=nothing,
    metadata::AbstractDict=Dict{String,Any}(),
)
    return ObjectRelationship(
        String(id),
        isnothing(name) ? nothing : String(name),
        isnothing(source) ? nothing : String(source),
        isnothing(target) ? nothing : String(target),
        isnothing(description) ? nothing : String(description),
        Dict{String,Any}(String(key) => value for (key, value) in pairs(metadata)),
    )
end

"""
A data property, optionally scoped to a concept by `domain`.
"""
struct DataProperty
    id::String
    name::Union{Nothing,String}
    value_type::Union{Nothing,String}
    description::Union{Nothing,String}
    domain::Union{Nothing,String}
    metadata::Dict{String,Any}
end

function DataProperty(
    id::AbstractString;
    name::Union{AbstractString,Nothing}=nothing,
    value_type::Union{AbstractString,Nothing}=nothing,
    description::Union{AbstractString,Nothing}=nothing,
    domain::Union{AbstractString,Nothing}=nothing,
    metadata::AbstractDict=Dict{String,Any}(),
)
    return DataProperty(
        String(id),
        isnothing(name) ? nothing : String(name),
        isnothing(value_type) ? nothing : String(value_type),
        isnothing(description) ? nothing : String(description),
        isnothing(domain) ? nothing : String(domain),
        Dict{String,Any}(String(key) => value for (key, value) in pairs(metadata)),
    )
end

"""
The complete intermediate representation passed from extraction to validation.
"""
struct IntermediateTemplate
    schema_version::String
    concepts::Vector{Concept}
    relationships::Vector{ObjectRelationship}
    properties::Vector{DataProperty}
    metadata::Dict{String,Any}
end

function IntermediateTemplate(;
    schema_version::AbstractString="1.0",
    concepts::AbstractVector{<:Concept}=Concept[],
    relationships::AbstractVector{<:ObjectRelationship}=ObjectRelationship[],
    properties::AbstractVector{<:DataProperty}=DataProperty[],
    metadata::AbstractDict=Dict{String,Any}(),
)
    return IntermediateTemplate(
        String(schema_version),
        Concept[concepts...],
        ObjectRelationship[relationships...],
        DataProperty[properties...],
        Dict{String,Any}(String(key) => value for (key, value) in pairs(metadata)),
    )
end

"""
A validation finding. `code` is stable for programmatic handling; `path` points
to the relevant template field.
"""
struct ValidationIssue
    code::Symbol
    path::String
    message::String
end
