export OntologyIndividual, OntologyRelationship, add_individual!, add_relationship!

mutable struct OntologyIndividual <: AbstractOntologyIndividual
    id::String
    types::Set{String}
    labels::Vector{String}
    definitions::Vector{String}
    annotations::Vector{Annotation}
end

function OntologyIndividual(
    id::AbstractString;
    types=String[],
    labels=String[],
    definitions=String[],
    annotations=Annotation[],
)
    return OntologyIndividual(
        String(id),
        _ontology_string_set(types, "types"),
        _ontology_strings(labels, "labels"),
        _ontology_strings(definitions, "definitions"),
        Annotation[annotations...],
    )
end

"""
An object-property assertion connecting a subject individual to an object individual.
"""
mutable struct OntologyRelationship <: AbstractOntologyRelationship
    subject::String
    predicate::String
    object::String
    annotations::Vector{Annotation}
end

function OntologyRelationship(
    subject::AbstractString,
    predicate::AbstractString,
    object::AbstractString;
    annotations=Annotation[],
)
    return OntologyRelationship(
        String(subject),
        String(predicate),
        String(object),
        Annotation[annotations...],
    )
end

function add_individual!(ontology::OntologyModel, individual::OntologyIndividual)
    identifier = _require_identifier(individual.id, "individual")
    haskey(ontology.individuals, identifier) &&
        throw(ArgumentError("individual '$identifier' already exists"))
    for type_id in individual.types
        haskey(ontology.classes, type_id) ||
            throw(ArgumentError("individual '$identifier' has unknown class '$type_id'"))
    end
    foreach(_require_annotation, individual.annotations)
    ontology.individuals[identifier] = individual
    return individual
end

add_individual!(ontology::OntologyModel, id::AbstractString; kwargs...) =
    add_individual!(ontology, OntologyIndividual(id; kwargs...))

function add_relationship!(ontology::OntologyModel, relationship::OntologyRelationship)
    isempty(strip(relationship.subject)) &&
        throw(ArgumentError("relationship subject must not be empty"))
    isempty(strip(relationship.predicate)) &&
        throw(ArgumentError("relationship predicate must not be empty"))
    isempty(strip(relationship.object)) &&
        throw(ArgumentError("relationship object must not be empty"))
    haskey(ontology.individuals, relationship.subject) ||
        throw(ArgumentError("unknown subject individual '$(relationship.subject)'"))
    haskey(ontology.object_properties, relationship.predicate) ||
        throw(ArgumentError("unknown object property '$(relationship.predicate)'"))
    haskey(ontology.individuals, relationship.object) ||
        throw(ArgumentError("unknown object individual '$(relationship.object)'"))
    foreach(_require_annotation, relationship.annotations)
    any(existing ->
        existing.subject == relationship.subject &&
        existing.predicate == relationship.predicate &&
        existing.object == relationship.object,
        ontology.relationships,
    ) && throw(ArgumentError("relationship assertion already exists"))
    push!(ontology.relationships, relationship)
    return relationship
end

function add_relationship!(
    ontology::OntologyModel,
    subject::AbstractString,
    predicate::AbstractString,
    object::AbstractString;
    annotations=Annotation[],
)
    return add_relationship!(
        ontology,
        OntologyRelationship(subject, predicate, object; annotations=annotations),
    )
end

const AnnotationTarget = Union{
    OntologyModel,
    AbstractOntologyClass,
    AbstractObjectProperty,
    AbstractDataProperty,
    AbstractOntologyIndividual,
    AbstractOntologyRelationship,
}

function add_annotation!(target::AnnotationTarget, annotation::Annotation)
    _require_annotation(annotation)
    push!(target.annotations, annotation)
    return annotation
end

add_annotation!(
    target::AnnotationTarget,
    property::AbstractString,
    value::AbstractString;
    kwargs...,
) = add_annotation!(target, Annotation(property, value; kwargs...))

function _validate_class_cycles!(issues, ontology)
    reported_cycles = Set{String}()
    state = Dict{String,UInt8}()
    path = String[]
    positions = Dict{String,Int}()

    function visit(identifier::String)
        state[identifier] = 0x01
        positions[identifier] = length(path) + 1
        push!(path, identifier)
        class = ontology.classes[identifier]::OntologyClass

        for parent_id in sort!(collect(class.superclasses))
            haskey(ontology.classes, parent_id) || continue
            parent_state = get(state, parent_id, 0x00)
            if parent_state == 0x00
                visit(parent_id)
            elseif parent_state == 0x01
                cycle = sort!(unique(path[positions[parent_id]:end]))
                cycle_key = join(cycle, "\0")
                if !(cycle_key in reported_cycles)
                    push!(reported_cycles, cycle_key)
                    push!(issues, OntologyValidationIssue(
                        :subclass_cycle,
                        "classes",
                        "subclass hierarchy contains a cycle involving: $(join(cycle, ", "))",
                    ))
                end
            end
        end

        pop!(path)
        delete!(positions, identifier)
        state[identifier] = 0x02
        return nothing
    end

    for identifier in sort!(collect(keys(ontology.classes)))
        get(state, identifier, 0x00) == 0x00 && visit(identifier)
    end
    return issues
end

function validate(ontology::OntologyModel)
    issues = OntologyValidationIssue[]
    if !isnothing(ontology.iri) && isempty(strip(ontology.iri))
        push!(issues, OntologyValidationIssue(:empty_iri, "iri", "ontology IRI must not be empty"))
    end
    if !isnothing(ontology.version) && isempty(strip(ontology.version))
        push!(issues, OntologyValidationIssue(:empty_version, "version", "ontology version must not be empty"))
    end
    _validate_texts!(issues, "ontology", "labels", ontology.labels)
    _validate_texts!(issues, "ontology", "definitions", ontology.definitions)
    _validate_annotations!(issues, "ontology", ontology.annotations)

    for (id, value) in ontology.classes
        class = value::OntologyClass
        path = "classes[$id]"
        _validate_identifier!(issues, "$path.id", class.id)
        class.id == id || push!(issues, OntologyValidationIssue(
            :identifier_mismatch,
            "$path.id",
            "class identifier does not match its registry key",
        ))
        _validate_texts!(issues, path, "labels", class.labels)
        _validate_texts!(issues, path, "definitions", class.definitions)
        _validate_annotations!(issues, path, class.annotations)
        _validate_class_references!(issues, ontology, path, "superclasses", class.superclasses)
    end
    _validate_class_cycles!(issues, ontology)

    for (id, value) in ontology.object_properties
        property = value::ObjectProperty
        path = "object_properties[$id]"
        _validate_identifier!(issues, "$path.id", property.id)
        property.id == id || push!(issues, OntologyValidationIssue(
            :identifier_mismatch,
            "$path.id",
            "object property identifier does not match its registry key",
        ))
        _validate_texts!(issues, path, "labels", property.labels)
        _validate_texts!(issues, path, "definitions", property.definitions)
        _validate_texts!(issues, path, "domains", property.domains)
        _validate_texts!(issues, path, "ranges", property.ranges)
        _validate_annotations!(issues, path, property.annotations)
        _validate_class_references!(issues, ontology, path, "domains", property.domains)
        _validate_class_references!(issues, ontology, path, "ranges", property.ranges)
    end

    for (id, value) in ontology.data_properties
        property = value::DataProperty
        path = "data_properties[$id]"
        _validate_identifier!(issues, "$path.id", property.id)
        property.id == id || push!(issues, OntologyValidationIssue(
            :identifier_mismatch,
            "$path.id",
            "data property identifier does not match its registry key",
        ))
        _validate_texts!(issues, path, "labels", property.labels)
        _validate_texts!(issues, path, "definitions", property.definitions)
        _validate_texts!(issues, path, "domains", property.domains)
        _validate_texts!(issues, path, "ranges", property.ranges)
        _validate_annotations!(issues, path, property.annotations)
        _validate_class_references!(issues, ontology, path, "domains", property.domains)
    end

    for (id, value) in ontology.individuals
        individual = value::OntologyIndividual
        path = "individuals[$id]"
        _validate_identifier!(issues, "$path.id", individual.id)
        individual.id == id || push!(issues, OntologyValidationIssue(
            :identifier_mismatch,
            "$path.id",
            "individual identifier does not match its registry key",
        ))
        _validate_texts!(issues, path, "labels", individual.labels)
        _validate_texts!(issues, path, "definitions", individual.definitions)
        _validate_annotations!(issues, path, individual.annotations)
        _validate_class_references!(issues, ontology, path, "types", individual.types)
    end

    seen_relationships = Set{Tuple{String,String,String}}()
    for (index, value) in enumerate(ontology.relationships)
        relationship = value::OntologyRelationship
        path = "relationships[$index]"
        for (field, identifier) in (
            ("subject", relationship.subject),
            ("predicate", relationship.predicate),
            ("object", relationship.object),
        )
            _validate_identifier!(issues, "$path.$field", identifier)
        end
        haskey(ontology.individuals, relationship.subject) ||
            push!(issues, OntologyValidationIssue(
                :invalid_reference,
                "$path.subject",
                "unknown subject individual '$(relationship.subject)'",
            ))
        haskey(ontology.object_properties, relationship.predicate) ||
            push!(issues, OntologyValidationIssue(
                :invalid_reference,
                "$path.predicate",
                "unknown object property '$(relationship.predicate)'",
            ))
        haskey(ontology.individuals, relationship.object) ||
            push!(issues, OntologyValidationIssue(
                :invalid_reference,
                "$path.object",
                "unknown object individual '$(relationship.object)'",
            ))
        _validate_annotations!(issues, path, relationship.annotations)
        triple = (relationship.subject, relationship.predicate, relationship.object)
        if triple in seen_relationships
            push!(issues, OntologyValidationIssue(
                :duplicate_relationship,
                path,
                "relationship assertion already exists",
            ))
        else
            push!(seen_relationships, triple)
        end
    end

    return issues
end

is_valid(ontology::OntologyModel) = isempty(validate(ontology))
