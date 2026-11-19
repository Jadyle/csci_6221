export add_class!, add_object_property!, add_data_property!, add_relationship!
export add_individual!, add_definition!, add_annotation!, add_restriction!

function _merge_texts(values, value, field::String)
    merged = Ontology._ontology_strings(values, field)
    if !isnothing(value)
        value isa AbstractString ||
            throw(ArgumentError("$field must be a string when provided"))
        push!(merged, String(value))
    end
    return merged
end

"""
Add a class and optional parent, labels, and definition to an ontology.
"""
function add_class!(
    ontology::Ontology.OntologyModel,
    id::AbstractString;
    name::Union{AbstractString,Nothing}=nothing,
    labels=String[],
    definition::Union{AbstractString,Nothing}=nothing,
    definitions=String[],
    parent::Union{AbstractString,Nothing}=nothing,
    annotations=Ontology.Annotation[],
)
    if !isnothing(parent) && !haskey(ontology.classes, String(parent))
        throw(ArgumentError("unknown parent class '$parent'"))
    end
    all_labels = _merge_texts(labels, name, "labels")
    all_definitions = _merge_texts(definitions, definition, "definitions")
    class = Ontology.OntologyClass(
        id;
        labels=all_labels,
        definitions=all_definitions,
        annotations=annotations,
    )
    Ontology.add_class!(ontology, class)
    !isnothing(parent) && Ontology.add_subclass!(ontology, id, parent)
    return class
end

"""
Add an object property. Domains and ranges refer to class identifiers already
present in the ontology.
"""
function add_object_property!(
    ontology::Ontology.OntologyModel,
    id::AbstractString;
    name::Union{AbstractString,Nothing}=nothing,
    labels=String[],
    definition::Union{AbstractString,Nothing}=nothing,
    definitions=String[],
    domains=String[],
    ranges=String[],
    annotations=Ontology.Annotation[],
)
    return Ontology.add_object_property!(
        ontology,
        id;
        labels=_merge_texts(labels, name, "labels"),
        definitions=_merge_texts(definitions, definition, "definitions"),
        domains=domains,
        ranges=ranges,
        annotations=annotations,
    )
end

"""
Add a data property. Its ranges may be XSD IRIs, known `xsd:` names, or
primitive aliases such as `string` and `number`.
"""
function add_data_property!(
    ontology::Ontology.OntologyModel,
    id::AbstractString;
    name::Union{AbstractString,Nothing}=nothing,
    labels=String[],
    definition::Union{AbstractString,Nothing}=nothing,
    definitions=String[],
    domains=String[],
    ranges=String[],
    value_type::Union{AbstractString,Nothing}=nothing,
    annotations=Ontology.Annotation[],
)
    all_ranges = _merge_texts(ranges, value_type, "ranges")
    return Ontology.add_data_property!(
        ontology,
        id;
        labels=_merge_texts(labels, name, "labels"),
        definitions=_merge_texts(definitions, definition, "definitions"),
        domains=domains,
        ranges=all_ranges,
        annotations=annotations,
    )
end

"""
Add an individual with optional class types, labels, and definition.
"""
function add_individual!(
    ontology::Ontology.OntologyModel,
    id::AbstractString;
    types=String[],
    labels=String[],
    name::Union{AbstractString,Nothing}=nothing,
    definition::Union{AbstractString,Nothing}=nothing,
    definitions=String[],
    annotations=Ontology.Annotation[],
)
    return Ontology.add_individual!(
        ontology,
        id;
        types=types,
        labels=_merge_texts(labels, name, "labels"),
        definitions=_merge_texts(definitions, definition, "definitions"),
        annotations=annotations,
    )
end

"""
Add an object-property assertion between two existing individuals.
"""
add_relationship!(
    ontology::Ontology.OntologyModel,
    subject::AbstractString,
    predicate::AbstractString,
    object::AbstractString;
    kwargs...,
) = Ontology.add_relationship!(ontology, subject, predicate, object; kwargs...)

function _enrichment_target(ontology, target, entity::Symbol)
    if entity == :ontology
        isnothing(target) ||
            throw(ArgumentError("target must be omitted for an ontology-level change"))
        return ontology
    end
    registry = if entity == :class
        ontology.classes
    elseif entity == :object_property
        ontology.object_properties
    elseif entity == :data_property
        ontology.data_properties
    elseif entity == :individual
        ontology.individuals
    else
        throw(ArgumentError(
            "entity must be :ontology, :class, :object_property, :data_property, or :individual",
        ))
    end
    identifier = String(target)
    haskey(registry, identifier) ||
        throw(ArgumentError("unknown $entity '$identifier'"))
    return registry[identifier]
end

"""
Add a definition to an ontology or to a class, property, or individual.
"""
function add_definition!(
    ontology::Ontology.OntologyModel,
    target::Union{AbstractString,Nothing},
    definition::AbstractString;
    entity::Symbol=:class,
)
    isempty(strip(definition)) && throw(ArgumentError("definition must not be empty"))
    target_object = _enrichment_target(ontology, target, entity)
    push!(target_object.definitions, String(definition))
    return definition
end

add_definition!(
    ontology::Ontology.OntologyModel,
    definition::AbstractString;
    entity::Symbol=:ontology,
) = add_definition!(ontology, nothing, definition; entity=entity)

"""
Add an annotation to an ontology or to a class, property, or individual.
"""
function add_annotation!(
    ontology::Ontology.OntologyModel,
    target::Union{AbstractString,Nothing},
    property::AbstractString,
    value::AbstractString;
    entity::Symbol=:class,
    language::Union{AbstractString,Nothing}=nothing,
    datatype::Union{AbstractString,Nothing}=nothing,
)
    target_object = _enrichment_target(ontology, target, entity)
    return Ontology.add_annotation!(
        target_object,
        Ontology.Annotation(property, value; language=language, datatype=datatype),
    )
end

add_annotation!(
    ontology::Ontology.OntologyModel,
    property::AbstractString,
    value::AbstractString;
    entity::Symbol=:ontology,
    kwargs...,
) = add_annotation!(ontology, nothing, property, value; entity=entity, kwargs...)

"""
Add an OWL class restriction to the ontology model.

Use `property_kind=:object` for object properties and `:data` for data
properties. Value restrictions use a class/datatype filler, an individual for
object-property `:has_value`, or a literal for data-property `:has_value`.
"""
add_restriction!(
    ontology::Ontology.OntologyModel,
    class::AbstractString,
    property::AbstractString;
    kwargs...,
) = Ontology.add_restriction!(ontology, class, property; kwargs...)
