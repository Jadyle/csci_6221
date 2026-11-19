export ObjectProperty, DataProperty, add_object_property!, add_data_property!

"""
An object property relates individuals and has class-valued domains and ranges.
"""
mutable struct ObjectProperty <: AbstractObjectProperty
    id::String
    labels::Vector{String}
    definitions::Vector{String}
    domains::Set{String}
    ranges::Set{String}
    annotations::Vector{Annotation}
end

function ObjectProperty(
    id::AbstractString;
    labels=String[],
    definitions=String[],
    domains=String[],
    ranges=String[],
    annotations=Annotation[],
)
    return ObjectProperty(
        String(id),
        _ontology_strings(labels, "labels"),
        _ontology_strings(definitions, "definitions"),
        _ontology_string_set(domains, "domains"),
        _ontology_string_set(ranges, "ranges"),
        Annotation[annotations...],
    )
end

"""
A data property has class-valued domains and datatype ranges.
"""
mutable struct DataProperty <: AbstractDataProperty
    id::String
    labels::Vector{String}
    definitions::Vector{String}
    domains::Set{String}
    ranges::Set{String}
    annotations::Vector{Annotation}
end

function DataProperty(
    id::AbstractString;
    labels=String[],
    definitions=String[],
    domains=String[],
    ranges=String[],
    annotations=Annotation[],
)
    return DataProperty(
        String(id),
        _ontology_strings(labels, "labels"),
        _ontology_strings(definitions, "definitions"),
        _ontology_string_set(domains, "domains"),
        _ontology_string_set(ranges, "ranges"),
        Annotation[annotations...],
    )
end

function _validate_property_class_refs(ontology, property, kind)
    for domain in property.domains
        isempty(strip(domain)) &&
            throw(ArgumentError("$kind '$(property.id)' has an empty domain identifier"))
        haskey(ontology.classes, domain) ||
            throw(ArgumentError("$kind '$(property.id)' has unknown domain class '$domain'"))
    end
    if kind == "object property"
        for range in property.ranges
            isempty(strip(range)) &&
                throw(ArgumentError("$kind '$(property.id)' has an empty range identifier"))
            haskey(ontology.classes, range) ||
                throw(ArgumentError("$kind '$(property.id)' has unknown range class '$range'"))
        end
    else
        for range in property.ranges
            isempty(strip(range)) &&
                throw(ArgumentError("$kind '$(property.id)' has an empty datatype range"))
        end
    end
    return property
end

function add_object_property!(ontology::OntologyModel, property::ObjectProperty)
    identifier = _require_identifier(property.id, "object property")
    haskey(ontology.object_properties, identifier) &&
        throw(ArgumentError("object property '$identifier' already exists"))
    _validate_property_class_refs(ontology, property, "object property")
    foreach(_require_annotation, property.annotations)
    ontology.object_properties[identifier] = property
    return property
end

add_object_property!(ontology::OntologyModel, id::AbstractString; kwargs...) =
    add_object_property!(ontology, ObjectProperty(id; kwargs...))

function add_data_property!(ontology::OntologyModel, property::DataProperty)
    identifier = _require_identifier(property.id, "data property")
    haskey(ontology.data_properties, identifier) &&
        throw(ArgumentError("data property '$identifier' already exists"))
    _validate_property_class_refs(ontology, property, "data property")
    foreach(_require_annotation, property.annotations)
    ontology.data_properties[identifier] = property
    return property
end

add_data_property!(ontology::OntologyModel, id::AbstractString; kwargs...) =
    add_data_property!(ontology, DataProperty(id; kwargs...))
