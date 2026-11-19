using Test
using RDF

const Enrichment = TaxonomyOntologyConverter.Enrichment
const Ontology = TaxonomyOntologyConverter.Ontology
const LLM = TaxonomyOntologyConverter.LLM

function enrichment_snapshot(ontology)
    return (
        sort!(collect(keys(ontology.classes))),
        sort!(collect(keys(ontology.object_properties))),
        sort!(collect(keys(ontology.data_properties))),
        sort!(collect(keys(ontology.individuals))),
        [(relationship.subject, relationship.predicate, relationship.object) for relationship in ontology.relationships],
        [
            (
                restriction.class,
                restriction.property,
                restriction.property_kind,
                restriction.kind,
                restriction.value,
                restriction.cardinality,
                restriction.datatype,
            ) for restriction in ontology.restrictions
        ],
    )
end

@testset "Manual ontology enrichment" begin
    ontology = Ontology.OntologyModel(iri="https://example.org/manual")
    Enrichment.add_class!(ontology, "Animal"; name="Animal")
    mammal = Enrichment.add_class!(
        ontology,
        "Mammal";
        name="mammal",
        definition="A warm-blooded vertebrate.",
        parent="Animal",
    )
    habitat = Enrichment.add_class!(ontology, "Habitat"; definition="An organism's environment.")
    lives_in = Enrichment.add_object_property!(
        ontology,
        "lives-in";
        name="lives in",
        domains=["Mammal"],
        ranges=["Habitat"],
    )
    age = Enrichment.add_data_property!(
        ontology,
        "age";
        value_type="integer",
        domains=["Mammal"],
    )
    fido = Enrichment.add_individual!(ontology, "fido"; types=["Mammal"], name="Fido")
    forest = Enrichment.add_individual!(ontology, "forest"; types=["Habitat"])
    assertion = Enrichment.add_relationship!(ontology, fido.id, lives_in.id, forest.id)
    Enrichment.add_definition!(ontology, "Mammal", "Has mammary glands.")
    Enrichment.add_definition!(ontology, "Manual ontology"; entity=:ontology)
    Enrichment.add_annotation!(ontology, "Mammal", "rdfs:seeAlso", "https://example.org/source")
    Enrichment.add_annotation!(ontology, "dcterms:creator", "Researcher"; entity=:ontology)
    some_habitat = Enrichment.add_restriction!(
        ontology,
        "Mammal",
        "lives-in";
        kind=:some_values_from,
        value="Habitat",
    )
    minimum_age = Enrichment.add_restriction!(
        ontology,
        "Mammal",
        "age";
        property_kind=:data,
        kind=:min_cardinality,
        cardinality=1,
    )

    @test mammal.superclasses == Set(["Animal"])
    @test habitat.id == "Habitat"
    @test assertion.subject == "fido"
    @test some_habitat.kind == :some_values_from
    @test minimum_age.cardinality == 1
    @test Ontology.is_valid(ontology)

    @test_throws ArgumentError Enrichment.add_class!(
        ontology,
        "Invalid child";
        parent="Missing",
    )
    @test !haskey(ontology.classes, "Invalid child")
    @test_throws ArgumentError Enrichment.add_definition!(ontology, "Missing", "definition")

    mktempdir() do directory
        path = joinpath(directory, "manual.owl")
        Enrichment.Ontology.save_ontology(ontology, path)
        @test isfile(path)
        graph = open(path, "r") do io
            read(io, :rdfxml, RDF.Graph)
        end
        @test !isempty(graph)
        restriction_type = RDF.IRI("http://www.w3.org/2002/07/owl#Restriction")
        on_property = RDF.IRI("http://www.w3.org/2002/07/owl#onProperty")
        minimum_cardinality = RDF.IRI("http://www.w3.org/2002/07/owl#minCardinality")
        age_iri = RDF.IRI("https://example.org/manual#age")
        cardinality_node = only([
            triple.subject for triple in graph
            if triple.predicate == RDF.IRI("http://www.w3.org/1999/02/22-rdf-syntax-ns#type") &&
               triple.object == restriction_type &&
               RDF.Triple(triple.subject, on_property, age_iri) in graph
        ])
        @test RDF.Triple(
            cardinality_node,
            minimum_cardinality,
            RDF.Literal(
                "1",
                RDF.IRI("http://www.w3.org/2001/XMLSchema#nonNegativeInteger"),
            ),
        ) in graph
    end
end

@testset "LLM-assisted enrichment proposals require review" begin
    ontology = Ontology.OntologyModel(iri="https://example.org/review")
    Ontology.add_class!(ontology, "Animal")
    initial = enrichment_snapshot(ontology)
    response = """
    {
      "suggestions": [
        {
          "action": "add_class",
          "payload": {
            "id": "Mammal",
            "name": "mammal",
            "definition": "A warm-blooded vertebrate.",
            "parent": "Animal"
          },
          "rationale": "The dataset defines mammals."
        },
        {
          "action": "add_data_property",
          "payload": {
            "id": "lifespan",
            "name": "lifespan",
            "domains": ["Mammal"],
            "value_type": "number",
            "definition": "Expected lifespan in years."
          },
          "rationale": "The dataset lists lifespan values."
        },
        {
          "action": "add_definition",
          "payload": {
            "entity": "class",
            "target": "Mammal",
            "definition": "A vertebrate that nurses its young."
          },
          "rationale": "Supported by the supplied notes."
        },
        {
          "action": "add_relationship",
          "payload": {
            "id": "lives-in",
            "name": "lives in",
            "source": "Mammal",
            "target": "Animal"
          },
          "rationale": "The dataset states that mammals live in habitats."
        },
        {
          "action": "add_restriction",
          "payload": {
            "class": "Mammal",
            "property": "lives-in",
            "property_kind": "object",
            "kind": "some_values_from",
            "value": "Animal"
          },
          "rationale": "The dataset associates mammals with animals."
        },
        {
          "action": "add_class",
          "payload": {
            "id": "UnreviewedClass",
            "name": "unreviewed"
          },
          "rationale": "This suggestion will not be accepted."
        }
      ]
    }
    """
    llm = LLM.MockLLM(response)
    proposal = Enrichment.propose_enrichment(llm, ontology, "Mammals, CSV, and field notes")

    @test proposal isa Enrichment.EnrichmentProposal
    @test getfield.(proposal.suggestions, :id) == ["s1", "s2", "s3", "s4", "s5", "s6"]
    @test enrichment_snapshot(ontology) == initial
    @test length(llm.prompts) == 1
    @test occursin("suggestions", only(llm.prompts))
    @test occursin("Mammals, CSV, and field notes", only(llm.prompts))
    @test occursin("do not write owl", lowercase(only(llm.prompts)))
    @test occursin("\"format\":\"text\"", only(llm.prompts))

    Enrichment.apply_suggestions!(ontology, proposal, ["s1", "s2", "s3", "s4", "s5"])
    @test haskey(ontology.classes, "Mammal")
    @test haskey(ontology.data_properties, "lifespan")
    @test haskey(ontology.object_properties, "lives-in")
    @test ontology.object_properties["lives-in"].domains == Set(["Mammal"])
    @test ontology.object_properties["lives-in"].ranges == Set(["Animal"])
    @test length(ontology.restrictions) == 1
    @test ontology.classes["Mammal"].definitions == [
        "A warm-blooded vertebrate.",
        "A vertebrate that nurses its young.",
    ]
    @test !haskey(ontology.classes, "UnreviewedClass")
    @test Ontology.is_valid(ontology)

    mktempdir() do directory
        path = joinpath(directory, "reviewed.owl")
        Enrichment.Ontology.save_ontology(ontology, path)
        @test isfile(path)
    end
end

@testset "Enrichment suggestion validation and atomic application" begin
    ontology = Ontology.OntologyModel(iri="https://example.org/atomic")
    Ontology.add_class!(ontology, "Existing")
    before = enrichment_snapshot(ontology)
    proposal = Enrichment.EnrichmentProposal([
        Enrichment.EnrichmentSuggestion(
            "s1",
            :add_class,
            Dict{String,Any}("id" => "Transient"),
            nothing,
        ),
        Enrichment.EnrichmentSuggestion(
            "s2",
            :add_class,
            Dict{String,Any}("id" => "Existing"),
            nothing,
        ),
    ])
    @test_throws ArgumentError Enrichment.apply_suggestions!(ontology, proposal, ["s2"])
    @test_throws ArgumentError Enrichment.apply_suggestions!(ontology, proposal, ["s1", "s2"])
    @test enrichment_snapshot(ontology) == before

    bad_response = LLM.MockLLM("""{"suggestions":[{"action":"generate_owl","payload":{}}]}""")
    @test_throws Enrichment.EnrichmentValidationError Enrichment.propose_enrichment(
        bad_response,
        ontology,
        Dict("records" => ["a", "b"]),
    )
    @test !isempty(bad_response.prompts)
    @test occursin("\"format\":\"json\"", only(bad_response.prompts))

    malformed_response = LLM.MockLLM("{not-json")
    @test_throws Enrichment.EnrichmentResponseError Enrichment.propose_enrichment(
        malformed_response,
        ontology,
        "notes",
    )
end
