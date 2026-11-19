export save_ontology, OntologySerializationError

struct OntologySerializationError <: Exception
    message::String
end

Base.showerror(io::IO, error::OntologySerializationError) = print(io, error.message)

const _RDF_NS = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
const _RDFS_NS = "http://www.w3.org/2000/01/rdf-schema#"
const _OWL_NS = "http://www.w3.org/2002/07/owl#"
const _XSD_NS = "http://www.w3.org/2001/XMLSchema#"
const _SKOS_NS = "http://www.w3.org/2004/02/skos/core#"
const _DC_NS = "http://purl.org/dc/elements/1.1/"
const _DCTERMS_NS = "http://purl.org/dc/terms/"

const _IRI_SCHEME = r"^[A-Za-z][A-Za-z0-9+.-]*:"
const _XML_NCNAME = r"^[A-Za-z_][A-Za-z0-9._-]*$"
const _KNOWN_PREFIXES = Dict(
    "rdf" => _RDF_NS,
    "rdfs" => _RDFS_NS,
    "owl" => _OWL_NS,
    "xsd" => _XSD_NS,
    "skos" => _SKOS_NS,
    "dc" => _DC_NS,
    "dcterms" => _DCTERMS_NS,
)
const _PREFERRED_XML_PREFIXES = Dict(
    _RDF_NS => "rdf",
    _RDFS_NS => "rdfs",
    _OWL_NS => "owl",
    _XSD_NS => "xsd",
    _SKOS_NS => "skos",
    _DC_NS => "dc",
    _DCTERMS_NS => "dcterms",
)
const _DATATYPE_ALIASES = Dict(
    "boolean" => "boolean",
    "bool" => "boolean",
    "date" => "date",
    "datetime" => "dateTime",
    "decimal" => "decimal",
    "double" => "double",
    "float" => "float",
    "int" => "integer",
    "integer" => "integer",
    "number" => "decimal",
    "string" => "string",
    "text" => "string",
)
const _RDF_TYPE = RDF.IRI(_RDF_NS * "type")
const _RDFS_LABEL = RDF.IRI(_RDFS_NS * "label")
const _RDFS_COMMENT = RDF.IRI(_RDFS_NS * "comment")
const _RDFS_SUBCLASS = RDF.IRI(_RDFS_NS * "subClassOf")
const _RDFS_DOMAIN = RDF.IRI(_RDFS_NS * "domain")
const _RDFS_RANGE = RDF.IRI(_RDFS_NS * "range")
const _OWL_ONTOLOGY = RDF.IRI(_OWL_NS * "Ontology")
const _OWL_CLASS = RDF.IRI(_OWL_NS * "Class")
const _OWL_OBJECT_PROPERTY = RDF.IRI(_OWL_NS * "ObjectProperty")
const _OWL_DATATYPE_PROPERTY = RDF.IRI(_OWL_NS * "DatatypeProperty")
const _OWL_NAMED_INDIVIDUAL = RDF.IRI(_OWL_NS * "NamedIndividual")
const _OWL_VERSION_INFO = RDF.IRI(_OWL_NS * "versionInfo")
const _OWL_AXIOM = RDF.IRI(_OWL_NS * "Axiom")
const _OWL_ANNOTATED_SOURCE = RDF.IRI(_OWL_NS * "annotatedSource")
const _OWL_ANNOTATED_PROPERTY = RDF.IRI(_OWL_NS * "annotatedProperty")
const _OWL_ANNOTATED_TARGET = RDF.IRI(_OWL_NS * "annotatedTarget")
const _METADATA_NS = "urn:taxonomy-ontology-converter:metadata:"
const _STRUCTURED_METADATA_KEYS = Set([
    "iri",
    "version",
    "label",
    "labels",
    "definition",
    "definitions",
])

function _expand_known_prefix(identifier::String)
    separator = findfirst(':', identifier)
    (isnothing(separator) || separator == firstindex(identifier)) && return identifier
    prefix = lowercase(identifier[firstindex(identifier):prevind(identifier, separator)])
    namespace = get(_KNOWN_PREFIXES, prefix, nothing)
    isnothing(namespace) && return identifier
    return namespace * identifier[nextind(identifier, separator):end]
end

function _percent_encode_identifier(identifier::String)
    io = IOBuffer()
    for byte in codeunits(identifier)
        if (UInt8('A') <= byte <= UInt8('Z')) ||
           (UInt8('a') <= byte <= UInt8('z')) ||
           (UInt8('0') <= byte <= UInt8('9')) ||
           byte in (UInt8('-'), UInt8('.'), UInt8('_'), UInt8('~'))
            write(io, byte)
        else
            write(io, '%')
            write(io, uppercase(string(byte; base=16, pad=2)))
        end
    end
    return String(take!(io))
end

function _ontology_iri(ontology::OntologyModel)
    isnothing(ontology.iri) && return nothing
    expanded = _expand_known_prefix(ontology.iri)
    occursin(_IRI_SCHEME, expanded) ||
        throw(ArgumentError("ontology IRI must be absolute; received '$(ontology.iri)'"))
    return RDF.IRI(expanded)
end

function _resolve_iri(ontology::OntologyModel, identifier::AbstractString)
    value = String(identifier)
    expanded = _expand_known_prefix(value)
    (expanded != value || occursin(_IRI_SCHEME, value)) && return RDF.IRI(expanded)

    base = _ontology_iri(ontology)
    isnothing(base) && throw(ArgumentError(
        "cannot resolve local identifier '$value' without an ontology IRI; set ontology.iri or use absolute entity IRIs",
    ))

    base_value = base.value
    if occursin(r"[?#]", base_value) &&
       !(endswith(base_value, "#") || endswith(base_value, "/"))
        throw(ArgumentError(
            "ontology IRI '$base_value' contains a query or fragment and cannot be used as a base for local identifiers",
        ))
    end
    separator = endswith(base_value, "#") || endswith(base_value, "/") ? "" : "#"
    return RDF.IRI(base_value * separator * _percent_encode_identifier(value))
end

function _datatype_iri(ontology::OntologyModel, identifier::AbstractString)
    alias = get(_DATATYPE_ALIASES, lowercase(String(identifier)), nothing)
    isnothing(alias) && return _resolve_iri(ontology, identifier)
    return RDF.IRI(_XSD_NS * alias)
end

function _annotation_literal(ontology::OntologyModel, annotation::Annotation)
    if !isnothing(annotation.language) && !isnothing(annotation.datatype)
        throw(ArgumentError(
            "annotation '$(annotation.property)' cannot specify both a language and a datatype",
        ))
    elseif !isnothing(annotation.language)
        return RDF.Literal(annotation.value; lang=annotation.language)
    elseif !isnothing(annotation.datatype)
        return RDF.Literal(annotation.value, _datatype_iri(ontology, annotation.datatype))
    end
    return RDF.Literal(annotation.value)
end

function _add_annotation!(
    graph::RDF.Graph,
    ontology::OntologyModel,
    subject::RDF.SubjectTerm,
    annotation::Annotation,
)
    predicate = _resolve_iri(ontology, annotation.property)
    object = _annotation_literal(ontology, annotation)
    push!(graph, RDF.Triple(subject, predicate, object))
    return graph
end

function _add_text_annotations!(graph, subject, predicate, values)
    for value in values
        push!(graph, RDF.Triple(subject, predicate, RDF.Literal(value)))
    end
    return graph
end

function _ontology_metadata_annotations!(graph, ontology, subject)
    for key in sort!(collect(keys(ontology.metadata)))
        key in _STRUCTURED_METADATA_KEYS && continue
        value = JSON.json(_canonical_json_value(ontology.metadata[key]))
        property = RDF.IRI(_METADATA_NS * _percent_encode_identifier(key))
        push!(graph, RDF.Triple(subject, property, RDF.Literal(value)))
    end
    return graph
end

function _ontology_graph(ontology::OntologyModel)
    issues = validate(ontology)
    if !isempty(issues)
        details = join(
            ("$(issue.path) [$(issue.code)]: $(issue.message)" for issue in issues),
            "\n- ",
        )
        throw(OntologySerializationError(
            "cannot serialize an invalid ontology:\n- $details",
        ))
    end

    graph = RDF.Graph()
    ontology_iri = _ontology_iri(ontology)
    blank_node_id = UInt64(1)
    ontology_node = if isnothing(ontology_iri)
        node = RDF.BlankNode(blank_node_id)
        blank_node_id += UInt64(1)
        node
    else
        ontology_iri
    end
    push!(graph, RDF.Triple(ontology_node, _RDF_TYPE, _OWL_ONTOLOGY))
    if !isnothing(ontology.version)
        push!(graph, RDF.Triple(ontology_node, _OWL_VERSION_INFO, RDF.Literal(ontology.version)))
    end
    _add_text_annotations!(graph, ontology_node, _RDFS_LABEL, ontology.labels)
    _add_text_annotations!(graph, ontology_node, _RDFS_COMMENT, ontology.definitions)
    foreach(annotation -> _add_annotation!(graph, ontology, ontology_node, annotation), ontology.annotations)
    _ontology_metadata_annotations!(graph, ontology, ontology_node)

    for identifier in sort!(collect(keys(ontology.classes)))
        class = ontology.classes[identifier]::OntologyClass
        subject = _resolve_iri(ontology, identifier)
        push!(graph, RDF.Triple(subject, _RDF_TYPE, _OWL_CLASS))
        _add_text_annotations!(graph, subject, _RDFS_LABEL, class.labels)
        _add_text_annotations!(graph, subject, _RDFS_COMMENT, class.definitions)
        for parent in sort!(collect(class.superclasses))
            push!(graph, RDF.Triple(subject, _RDFS_SUBCLASS, _resolve_iri(ontology, parent)))
        end
        foreach(annotation -> _add_annotation!(graph, ontology, subject, annotation), class.annotations)
    end

    for identifier in sort!(collect(keys(ontology.object_properties)))
        property = ontology.object_properties[identifier]::ObjectProperty
        subject = _resolve_iri(ontology, identifier)
        push!(graph, RDF.Triple(subject, _RDF_TYPE, _OWL_OBJECT_PROPERTY))
        _add_text_annotations!(graph, subject, _RDFS_LABEL, property.labels)
        _add_text_annotations!(graph, subject, _RDFS_COMMENT, property.definitions)
        for domain in sort!(collect(property.domains))
            push!(graph, RDF.Triple(subject, _RDFS_DOMAIN, _resolve_iri(ontology, domain)))
        end
        for range in sort!(collect(property.ranges))
            push!(graph, RDF.Triple(subject, _RDFS_RANGE, _resolve_iri(ontology, range)))
        end
        foreach(annotation -> _add_annotation!(graph, ontology, subject, annotation), property.annotations)
    end

    for identifier in sort!(collect(keys(ontology.data_properties)))
        property = ontology.data_properties[identifier]::DataProperty
        subject = _resolve_iri(ontology, identifier)
        push!(graph, RDF.Triple(subject, _RDF_TYPE, _OWL_DATATYPE_PROPERTY))
        _add_text_annotations!(graph, subject, _RDFS_LABEL, property.labels)
        _add_text_annotations!(graph, subject, _RDFS_COMMENT, property.definitions)
        for domain in sort!(collect(property.domains))
            push!(graph, RDF.Triple(subject, _RDFS_DOMAIN, _resolve_iri(ontology, domain)))
        end
        for range in sort!(collect(property.ranges))
            push!(graph, RDF.Triple(subject, _RDFS_RANGE, _datatype_iri(ontology, range)))
        end
        foreach(annotation -> _add_annotation!(graph, ontology, subject, annotation), property.annotations)
    end

    for identifier in sort!(collect(keys(ontology.individuals)))
        individual = ontology.individuals[identifier]::OntologyIndividual
        subject = _resolve_iri(ontology, identifier)
        push!(graph, RDF.Triple(subject, _RDF_TYPE, _OWL_NAMED_INDIVIDUAL))
        _add_text_annotations!(graph, subject, _RDFS_LABEL, individual.labels)
        _add_text_annotations!(graph, subject, _RDFS_COMMENT, individual.definitions)
        for type_id in sort!(collect(individual.types))
            push!(graph, RDF.Triple(subject, _RDF_TYPE, _resolve_iri(ontology, type_id)))
        end
        foreach(annotation -> _add_annotation!(graph, ontology, subject, annotation), individual.annotations)
    end

    for relationship in sort!(
        copy(ontology.relationships);
        by=relationship -> (relationship.subject, relationship.predicate, relationship.object),
    )
        source = _resolve_iri(ontology, relationship.subject)
        predicate = _resolve_iri(ontology, relationship.predicate)
        target = _resolve_iri(ontology, relationship.object)
        push!(graph, RDF.Triple(source, predicate, target))
        isempty(relationship.annotations) && continue

        axiom = RDF.BlankNode(blank_node_id)
        blank_node_id += UInt64(1)
        push!(graph, RDF.Triple(axiom, _RDF_TYPE, _OWL_AXIOM))
        push!(graph, RDF.Triple(axiom, _OWL_ANNOTATED_SOURCE, source))
        push!(graph, RDF.Triple(axiom, _OWL_ANNOTATED_PROPERTY, predicate))
        push!(graph, RDF.Triple(axiom, _OWL_ANNOTATED_TARGET, target))
        foreach(annotation -> _add_annotation!(graph, ontology, axiom, annotation), relationship.annotations)
    end

    return graph
end

function _term_sort_key(term::RDF.IRI)
    return (1, term.value, "", "")
end

function _term_sort_key(term::RDF.BlankNode)
    return (2, string(term.id), "", "")
end

function _term_sort_key(term::RDF.Literal)
    return (3, term.lexical_form, term.datatype.value, term.language_tag)
end

function _predicate_qname(iri::RDF.IRI)
    value = iri.value
    for start in eachindex(value)
        start == firstindex(value) && continue
        local_name = value[start:end]
        if occursin(_XML_NCNAME, local_name)
            namespace = value[firstindex(value):prevind(value, start)]
            return namespace, local_name
        end
    end
    throw(ArgumentError(
        "RDF predicate IRI '$value' cannot be represented as an RDF/XML QName",
    ))
end

function _rdfxml_document(graph::RDF.Graph)
    triples = collect(graph)
    qnames = Dict{String,Tuple{String,String}}()
    namespaces = Set{String}()
    for triple in triples
        namespace, local_name = _predicate_qname(triple.predicate)
        qnames[triple.predicate.value] = (namespace, local_name)
        push!(namespaces, namespace)
    end

    prefix_by_namespace = Dict{String,String}()
    for namespace in sort!(collect(namespaces))
        prefix = get(_PREFERRED_XML_PREFIXES, namespace, nothing)
        if isnothing(prefix)
            index = 1
            while "ns$index" in values(prefix_by_namespace)
                index += 1
            end
            prefix = "ns$index"
        end
        prefix_by_namespace[namespace] = prefix
    end

    document = EzXML.XMLDocument()
    root = EzXML.ElementNode("rdf:RDF")
    EzXML.setroot!(document, root)
    root["xmlns:rdf"] = _RDF_NS
    for namespace in sort!(collect(keys(prefix_by_namespace)))
        prefix_by_namespace[namespace] == "rdf" && continue
        root["xmlns:$(prefix_by_namespace[namespace])"] = namespace
    end

    by_subject = Dict{Any,Vector{RDF.Triple}}()
    for triple in triples
        push!(get!(by_subject, triple.subject, RDF.Triple[]), triple)
    end

    for subject in sort!(collect(keys(by_subject)); by=_term_sort_key)
        description = EzXML.ElementNode("rdf:Description")
        if subject isa RDF.IRI
            description["rdf:about"] = subject.value
        else
            description["rdf:nodeID"] = "b$(subject.id)"
        end
        EzXML.link!(root, description)

        subject_triples = by_subject[subject]
        sort!(subject_triples; by=triple -> (
            triple.predicate.value,
            _term_sort_key(triple.object),
        ))
        for triple in subject_triples
            namespace, local_name = qnames[triple.predicate.value]
            property = EzXML.ElementNode("$(prefix_by_namespace[namespace]):$local_name")
            EzXML.link!(description, property)
            if triple.object isa RDF.IRI
                property["rdf:resource"] = triple.object.value
            elseif triple.object isa RDF.BlankNode
                property["rdf:nodeID"] = "b$(triple.object.id)"
            else
                literal = triple.object::RDF.Literal
                if !isempty(literal.language_tag)
                    property["xml:lang"] = literal.language_tag
                else
                    property["rdf:datatype"] = literal.datatype.value
                end
                EzXML.setnodecontent!(property, literal.lexical_form)
            end
        end
    end

    return document
end

"""
    save_ontology(ontology::OntologyModel, path::AbstractString)

Serialize an ontology model as RDF/XML in an `.owl` file that can be opened in
Protégé. Local entity identifiers are resolved against `ontology.iri`.
"""
function save_ontology(ontology::OntologyModel, path::AbstractString)
    graph = _ontology_graph(ontology)
    document = _rdfxml_document(graph)
    output_path = String(path)
    mkpath(dirname(output_path))
    open(output_path, "w") do io
        EzXML.prettyprint(io, document)
        println(io)
    end
    return output_path
end
