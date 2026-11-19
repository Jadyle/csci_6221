function _required_text_issue!(issues::Vector{ValidationIssue}, path::String, field::String, value)
    if isnothing(value)
        push!(issues, ValidationIssue(:missing_required_field, path, "$field is required"))
    elseif isempty(strip(value))
        push!(issues, ValidationIssue(:empty_required_field, path, "$field must not be empty"))
    end
    return issues
end

function _validate_concept(concept::Concept, path::String)
    issues = ValidationIssue[]
    _required_text_issue!(issues, "$path.id", "id", concept.id)

    if !isnothing(concept.name) && isempty(strip(concept.name))
        push!(issues, ValidationIssue(:empty_label, "$path.name", "name must not be empty"))
    end

    for (index, label) in enumerate(concept.labels)
        if isempty(strip(label))
            push!(issues, ValidationIssue(:empty_label, "$path.labels[$index]", "label must not be empty"))
        end
    end

    has_name = !isnothing(concept.name) && !isempty(strip(concept.name))
    has_label = any(label -> !isempty(strip(label)), concept.labels)
    if !has_name && !has_label
        push!(issues, ValidationIssue(:missing_label, path, "concept must have a name or at least one non-empty label"))
    end

    return issues
end

function _validate_relationship(relationship::ObjectRelationship, path::String)
    issues = ValidationIssue[]
    _required_text_issue!(issues, "$path.id", "id", relationship.id)
    _required_text_issue!(issues, "$path.name", "name", relationship.name)
    _required_text_issue!(issues, "$path.source", "source", relationship.source)
    _required_text_issue!(issues, "$path.target", "target", relationship.target)
    return issues
end

function _validate_property(property::DataProperty, path::String)
    issues = ValidationIssue[]
    _required_text_issue!(issues, "$path.id", "id", property.id)
    _required_text_issue!(issues, "$path.name", "name", property.name)
    _required_text_issue!(issues, "$path.type", "type", property.value_type)
    if !isnothing(property.domain) && isempty(strip(property.domain))
        push!(issues, ValidationIssue(:empty_required_field, "$path.domain", "domain must not be empty when provided"))
    end
    return issues
end

"""
    validate(value)

Return validation issues for a concept, object relationship, data property, or
complete intermediate template. Incomplete extracted records remain representable
and are reported here instead of being rejected by their constructors.
"""
validate(concept::Concept) = _validate_concept(concept, "concept")
validate(relationship::ObjectRelationship) = _validate_relationship(relationship, "relationship")
validate(property::DataProperty) = _validate_property(property, "property")

function _reference_issue!(issues, path, field, target, concept_ids)
    if !isnothing(target) && !isempty(strip(target)) && !(target in concept_ids)
        push!(issues, ValidationIssue(
            :invalid_reference,
            path,
            "$field references unknown concept identifier '$target'",
        ))
    end
    return issues
end

function _parent_cycle_issues!(issues, concepts, concepts_by_id)
    reported_cycles = Set{String}()
    for concept in concepts
        isempty(strip(concept.id)) && continue
        order = String[]
        positions = Dict{String,Int}()
        current_id = concept.id

        while haskey(concepts_by_id, current_id)
            if haskey(positions, current_id)
                cycle = sort!(unique(order[positions[current_id]:end]))
                cycle_key = join(cycle, "\0")
                if !(cycle_key in reported_cycles)
                    push!(reported_cycles, cycle_key)
                    push!(issues, ValidationIssue(
                        :parent_cycle,
                        "concepts",
                        "parent hierarchy contains a cycle involving: $(join(cycle, ", "))",
                    ))
                end
                break
            end

            positions[current_id] = length(order) + 1
            push!(order, current_id)
            parent_id = concepts_by_id[current_id].parent
            if isnothing(parent_id) || !haskey(concepts_by_id, parent_id)
                break
            end
            current_id = parent_id
        end
    end
    return issues
end

function validate(template::IntermediateTemplate)
    issues = ValidationIssue[]
    _required_text_issue!(issues, "schema_version", "schema_version", template.schema_version)

    all_ids = Dict{String,String}()
    for (kind, entities) in (
        ("concept", template.concepts),
        ("relationship", template.relationships),
        ("property", template.properties),
    )
        for (index, entity) in enumerate(entities)
            path = "$(kind)s[$index]"
            append!(issues, kind == "concept" ? _validate_concept(entity, path) :
                kind == "relationship" ? _validate_relationship(entity, path) :
                _validate_property(entity, path))

            id = entity.id
            if !isempty(strip(id))
                if haskey(all_ids, id)
                    push!(issues, ValidationIssue(
                        :duplicate_identifier,
                        "$path.id",
                        "identifier '$id' is already used by $(all_ids[id])",
                    ))
                else
                    all_ids[id] = path
                end
            end
        end
    end

    concepts_by_id = Dict{String,Concept}()
    for concept in template.concepts
        isempty(strip(concept.id)) || (concepts_by_id[concept.id] = concept)
    end
    concept_ids = Set(keys(concepts_by_id))

    for (index, concept) in enumerate(template.concepts)
        path = "concepts[$index].parent"
        _reference_issue!(issues, path, "parent", concept.parent, concept_ids)
    end
    _parent_cycle_issues!(issues, template.concepts, concepts_by_id)

    for (index, relationship) in enumerate(template.relationships)
        path = "relationships[$index]"
        _reference_issue!(issues, "$path.source", "source", relationship.source, concept_ids)
        _reference_issue!(issues, "$path.target", "target", relationship.target, concept_ids)
    end

    for (index, property) in enumerate(template.properties)
        _reference_issue!(issues, "properties[$index].domain", "domain", property.domain, concept_ids)
    end

    return issues
end

is_valid(value) = isempty(validate(value))
