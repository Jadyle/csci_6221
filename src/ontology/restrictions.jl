export add_restriction!

"""
Add a restriction to a class. References are checked against the existing
class, property, filler, or individual registries before the restriction is stored.
"""
function add_restriction!(
    ontology::OntologyModel,
    restriction::OntologyRestriction,
)
    haskey(ontology.classes, restriction.class) ||
        throw(ArgumentError("unknown class '$(restriction.class)'"))

    property_registry = if restriction.property_kind == :object
        ontology.object_properties
    else
        ontology.data_properties
    end
    haskey(property_registry, restriction.property) ||
        throw(ArgumentError(
            "unknown $(restriction.property_kind) property '$(restriction.property)'",
        ))

    if restriction.property_kind == :object
        if restriction.kind in (:some_values_from, :all_values_from)
            haskey(ontology.classes, something(restriction.value)) ||
                throw(ArgumentError("unknown restriction filler class '$(restriction.value)'"))
        elseif restriction.kind == :has_value
            haskey(ontology.individuals, something(restriction.value)) ||
                throw(ArgumentError("unknown restriction value individual '$(restriction.value)'"))
        end
    end

    any(existing -> existing == restriction, ontology.restrictions) &&
        throw(ArgumentError("restriction already exists"))
    push!(ontology.restrictions, restriction)
    return restriction
end

function add_restriction!(
    ontology::OntologyModel,
    class::AbstractString,
    property::AbstractString;
    kwargs...,
)
    return add_restriction!(
        ontology,
        OntologyRestriction(class, property; kwargs...),
    )
end

function _validate_restrictions!(issues, ontology)
    for (index, restriction) in enumerate(ontology.restrictions)
        path = "restrictions[$index]"
        _validate_identifier!(issues, "$path.class", restriction.class)
        _validate_identifier!(issues, "$path.property", restriction.property)

        haskey(ontology.classes, restriction.class) ||
            push!(issues, OntologyValidationIssue(
                :invalid_reference,
                "$path.class",
                "unknown restriction class '$(restriction.class)'",
            ))

        property_registry = if restriction.property_kind == :object
            ontology.object_properties
        elseif restriction.property_kind == :data
            ontology.data_properties
        else
            push!(issues, OntologyValidationIssue(
                :invalid_restriction,
                "$path.property_kind",
                "property kind must be :object or :data",
            ))
            nothing
        end
        if !isnothing(property_registry) && !haskey(property_registry, restriction.property)
            push!(issues, OntologyValidationIssue(
                :invalid_reference,
                "$path.property",
                "unknown $(restriction.property_kind) property '$(restriction.property)'",
            ))
        end

        if restriction.kind in (:some_values_from, :all_values_from)
            if isnothing(restriction.value) || isempty(strip(restriction.value))
                push!(issues, OntologyValidationIssue(
                    :invalid_restriction,
                    "$path.value",
                    "value restriction requires a non-empty filler",
                ))
            elseif restriction.property_kind == :object &&
                   !haskey(ontology.classes, restriction.value)
                push!(issues, OntologyValidationIssue(
                    :invalid_reference,
                    "$path.value",
                    "unknown restriction filler class '$(restriction.value)'",
                ))
            end
        elseif restriction.kind == :has_value
            if isnothing(restriction.value) || isempty(strip(restriction.value))
                push!(issues, OntologyValidationIssue(
                    :invalid_restriction,
                    "$path.value",
                    "has-value restriction requires a non-empty value",
                ))
            elseif restriction.property_kind == :object &&
                   !haskey(ontology.individuals, restriction.value)
                push!(issues, OntologyValidationIssue(
                    :invalid_reference,
                    "$path.value",
                    "unknown restriction value individual '$(restriction.value)'",
                ))
            end
        elseif restriction.kind in (:min_cardinality, :max_cardinality, :exact_cardinality)
            if isnothing(restriction.cardinality) || restriction.cardinality < 0
                push!(issues, OntologyValidationIssue(
                    :invalid_restriction,
                    "$path.cardinality",
                    "cardinality must be a non-negative integer",
                ))
            end
        else
            push!(issues, OntologyValidationIssue(
                :invalid_restriction,
                "$path.kind",
                "unsupported restriction kind '$(restriction.kind)'",
            ))
        end

        if !isnothing(restriction.datatype) &&
           (restriction.kind != :has_value || restriction.property_kind != :data)
            push!(issues, OntologyValidationIssue(
                :invalid_restriction,
                "$path.datatype",
                "datatype is only valid for data-property has-value restrictions",
            ))
        end
        if !isnothing(restriction.datatype) && isempty(strip(restriction.datatype))
            push!(issues, OntologyValidationIssue(
                :invalid_restriction,
                "$path.datatype",
                "datatype must not be empty",
            ))
        end
        if restriction.kind == :has_value &&
           restriction.property_kind == :data &&
           isnothing(restriction.datatype) &&
           haskey(ontology.data_properties, restriction.property)
            property = ontology.data_properties[restriction.property]::DataProperty
            if length(property.ranges) > 1
                push!(issues, OntologyValidationIssue(
                    :invalid_restriction,
                    "$path.datatype",
                    "data-property has-value restriction needs an explicit datatype when the property has multiple ranges",
                ))
            end
        end
    end
    return issues
end
