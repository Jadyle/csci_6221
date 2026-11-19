export OntologyClass, add_class!, add_subclass!

"""
An ontology class with labels, definitions, superclass identifiers, and annotations.
"""
mutable struct OntologyClass <: AbstractOntologyClass
    id::String
    labels::Vector{String}
    definitions::Vector{String}
    superclasses::Set{String}
    annotations::Vector{Annotation}
end

function OntologyClass(
    id::AbstractString;
    labels=String[],
    definitions=String[],
    annotations=Annotation[],
)
    return OntologyClass(
        String(id),
        _ontology_strings(labels, "labels"),
        _ontology_strings(definitions, "definitions"),
        Set{String}(),
        Annotation[annotations...],
    )
end

"""
Add a class to an ontology. Its identifier must be non-empty and unique among classes.
"""
function add_class!(ontology::OntologyModel, class::OntologyClass)
    identifier = _require_identifier(class.id, "class")
    haskey(ontology.classes, identifier) &&
        throw(ArgumentError("class '$identifier' already exists"))
    isempty(class.superclasses) ||
        throw(ArgumentError("use add_subclass! to add superclass relationships"))
    foreach(_require_annotation, class.annotations)
    ontology.classes[identifier] = class
    return class
end

add_class!(ontology::OntologyModel, id::AbstractString; kwargs...) =
    add_class!(ontology, OntologyClass(id; kwargs...))

function _is_subclass_of(ontology::OntologyModel, child::String, ancestor::String)
    pending = String[child]
    visited = Set{String}()
    while !isempty(pending)
        current = pop!(pending)
        current == ancestor && return true
        current in visited && continue
        push!(visited, current)
        class = ontology.classes[current]::OntologyClass
        append!(pending, class.superclasses)
    end
    return false
end

"""
Declare `child_id` as a subclass of `parent_id`.

Both classes must already exist, and the operation rejects self-inheritance and cycles.
"""
function add_subclass!(ontology::OntologyModel, child_id::AbstractString, parent_id::AbstractString)
    child_key = String(child_id)
    parent_key = String(parent_id)
    haskey(ontology.classes, child_key) ||
        throw(ArgumentError("unknown child class '$child_key'"))
    haskey(ontology.classes, parent_key) ||
        throw(ArgumentError("unknown parent class '$parent_key'"))
    child_key == parent_key &&
        throw(ArgumentError("a class cannot be its own superclass"))
    _is_subclass_of(ontology, parent_key, child_key) &&
        throw(ArgumentError("adding '$child_key' as a subclass of '$parent_key' would create a cycle"))

    child = ontology.classes[child_key]::OntologyClass
    push!(child.superclasses, parent_key)
    return child
end
