to_dict(concept::Concept) = Dict{String,Any}(
    "id" => concept.id,
    "name" => concept.name,
    "labels" => concept.labels,
    "description" => concept.description,
    "parent" => concept.parent,
    "metadata" => concept.metadata,
)

to_dict(relationship::ObjectRelationship) = Dict{String,Any}(
    "id" => relationship.id,
    "name" => relationship.name,
    "source" => relationship.source,
    "target" => relationship.target,
    "description" => relationship.description,
    "metadata" => relationship.metadata,
)

to_dict(property::DataProperty) = Dict{String,Any}(
    "id" => property.id,
    "name" => property.name,
    "type" => property.value_type,
    "description" => property.description,
    "domain" => property.domain,
    "metadata" => property.metadata,
)

function to_dict(template::IntermediateTemplate)
    return Dict{String,Any}(
        "schema_version" => template.schema_version,
        "concepts" => to_dict.(template.concepts),
        "relationships" => to_dict.(template.relationships),
        "properties" => to_dict.(template.properties),
        "metadata" => template.metadata,
    )
end

to_json(template::IntermediateTemplate) = JSON.json(to_dict(template))

function _json_object(value, path::String)
    value isa AbstractDict || throw(ArgumentError("$path must be a JSON object"))
    result = Dict{String,Any}()
    for (key, item) in pairs(value)
        key isa AbstractString || throw(ArgumentError("$path keys must be strings"))
        result[String(key)] = item
    end
    return result
end

function _text_field(object, key::String, path::String; required::Bool=false, default=nothing)
    value = get(object, key, default)
    if isnothing(value)
        required && throw(ArgumentError("$path.$key is required and must be a string"))
        return nothing
    end
    value isa AbstractString || throw(ArgumentError("$path.$key must be a string or null"))
    return String(value)
end

function _string_list_field(object, key::String, path::String)
    value = get(object, key, String[])
    isnothing(value) && return String[]
    value isa AbstractVector || throw(ArgumentError("$path.$key must be an array of strings or null"))
    all(item -> item isa AbstractString, value) ||
        throw(ArgumentError("$path.$key must contain only strings"))
    return String[String(item) for item in value]
end

function _metadata_field(object, path::String)
    value = get(object, "metadata", Dict{String,Any}())
    isnothing(value) && return Dict{String,Any}()
    return _json_object(value, "$path.metadata")
end

function _from_concept(value, path::String)
    object = _json_object(value, path)
    return Concept(
        _text_field(object, "id", path; required=true);
        name=_text_field(object, "name", path),
        labels=_string_list_field(object, "labels", path),
        description=_text_field(object, "description", path),
        parent=_text_field(object, "parent", path),
        metadata=_metadata_field(object, path),
    )
end

function _from_relationship(value, path::String)
    object = _json_object(value, path)
    return ObjectRelationship(
        _text_field(object, "id", path; required=true);
        name=_text_field(object, "name", path),
        source=_text_field(object, "source", path),
        target=_text_field(object, "target", path),
        description=_text_field(object, "description", path),
        metadata=_metadata_field(object, path),
    )
end

function _from_property(value, path::String)
    object = _json_object(value, path)
    return DataProperty(
        _text_field(object, "id", path; required=true);
        name=_text_field(object, "name", path),
        value_type=_text_field(object, "type", path),
        description=_text_field(object, "description", path),
        domain=_text_field(object, "domain", path),
        metadata=_metadata_field(object, path),
    )
end

function _list_field(object, key::String, path::String)
    value = get(object, key, Any[])
    isnothing(value) && return Any[]
    value isa AbstractVector || throw(ArgumentError("$path.$key must be an array or null"))
    return value
end

"""
    from_dict(value)

Construct an intermediate template from a dictionary, such as the result of
`JSON.parse`. Semantic checks are performed separately by `validate`.
"""
function from_dict(value)
    object = _json_object(value, "template")
    concepts = Concept[
        _from_concept(item, "concepts[$index]") for
        (index, item) in enumerate(_list_field(object, "concepts", "template"))
    ]
    relationships = ObjectRelationship[
        _from_relationship(item, "relationships[$index]") for
        (index, item) in enumerate(_list_field(object, "relationships", "template"))
    ]
    properties = DataProperty[
        _from_property(item, "properties[$index]") for
        (index, item) in enumerate(_list_field(object, "properties", "template"))
    ]

    schema_version = _text_field(object, "schema_version", "template"; default="1.0")
    isnothing(schema_version) &&
        throw(ArgumentError("template.schema_version must be a string when provided"))

    return IntermediateTemplate(
        schema_version=schema_version,
        concepts=concepts,
        relationships=relationships,
        properties=properties,
        metadata=_metadata_field(object, "template"),
    )
end

from_json(json::AbstractString) = from_dict(JSON.parse(json))
from_json(io::IO) = from_json(read(io, String))
