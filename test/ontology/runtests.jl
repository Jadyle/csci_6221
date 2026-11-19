using Test
using RDF

const Ontology = TaxonomyOntologyConverter.Ontology
const Template = TaxonomyOntologyConverter.Template

function ontology_snapshot(ontology)
    class_snapshot = sort([
        (
            id,
            class.labels,
            class.definitions,
            sort!(collect(class.superclasses)),
            [(a.property, a.value, a.language, a.datatype) for a in class.annotations],
        ) for (id, class) in ontology.classes
    ]; by=first)
    object_property_snapshot = sort([
        (
            id,
            property.labels,
            property.definitions,
            sort!(collect(property.domains)),
            sort!(collect(property.ranges)),
            [(a.property, a.value, a.language, a.datatype) for a in property.annotations],
        ) for (id, property) in ontology.object_properties
    ]; by=first)
    data_property_snapshot = sort([
        (
            id,
            property.labels,
            property.definitions,
            sort!(collect(property.domains)),
            sort!(collect(property.ranges)),
            [(a.property, a.value, a.language, a.datatype) for a in property.annotations],
        ) for (id, property) in ontology.data_properties
    ]; by=first)
    return (
        ontology.iri,
        ontology.version,
        ontology.labels,
        ontology.definitions,
        ontology.metadata,
        class_snapshot,
        object_property_snapshot,
        data_property_snapshot,
        sort!(collect(keys(ontology.individuals))),
        [(r.subject, r.predicate, r.object) for r in ontology.relationships],
    )
end

@testset "Ontology model" begin
    @testset "constructing a semantically valid ontology" begin
        ontology = Ontology.OntologyModel(
            iri="https://example.org/ecology",
            version="1.0",
            labels=["Ecology"],
            definitions=["A small example ontology."],
            metadata=Dict("source" => "unit test"),
        )
        organism = Ontology.add_class!(
            ontology,
            "Organism";
            labels=["organism"],
            definitions=["A living thing."],
        )
        tree = Ontology.add_class!(
            ontology,
            "Tree";
            labels=["tree"],
            definitions=["A woody perennial plant."],
        )
        habitat = Ontology.add_class!(ontology, "Habitat"; labels=["habitat"])
        Ontology.add_subclass!(ontology, "Tree", "Organism")

        lives_in = Ontology.add_object_property!(
            ontology,
            "lives-in";
            labels=["lives in"],
            domains=["Tree"],
            ranges=["Habitat"],
        )
        height = Ontology.add_data_property!(
            ontology,
            "height";
            labels=["height"],
            definitions=["Typical height."],
            domains=["Tree"],
            ranges=["xsd:decimal"],
        )
        oak = Ontology.add_individual!(
            ontology,
            "oak-1";
            types=["Tree"],
            labels=["Oak 1"],
        )
        forest = Ontology.add_individual!(
            ontology,
            "forest-1";
            types=["Habitat"],
        )
        assertion = Ontology.add_relationship!(ontology, "oak-1", "lives-in", "forest-1")

        Ontology.add_annotation!(ontology, "dcterms:creator", "Research group")
        Ontology.add_annotation!(tree, "rdfs:comment", "Extracted from a sample taxonomy."; language="en")

        @test ontology.classes["Organism"] === organism
        @test tree.superclasses == Set(["Organism"])
        @test lives_in.domains == Set(["Tree"])
        @test height.ranges == Set(["xsd:decimal"])
        @test oak.types == Set(["Tree"])
        @test assertion.subject == "oak-1"
        @test forest.id == "forest-1"
        @test length(ontology.annotations) == 1
        @test isempty(Ontology.validate(ontology))
        @test Ontology.is_valid(ontology)
    end

    @testset "rejecting duplicate identifiers and invalid references" begin
        ontology = Ontology.OntologyModel()
        Ontology.add_class!(ontology, "Plant")
        @test_throws ArgumentError Ontology.add_class!(ontology, "Plant")
        @test_throws ArgumentError Ontology.add_subclass!(ontology, "Plant", "Missing")
        @test_throws ArgumentError Ontology.add_subclass!(ontology, "Plant", "Plant")
        @test_throws ArgumentError Ontology.add_object_property!(
            ontology,
            "has-habitat";
            domains=["Missing"],
        )
        @test_throws ArgumentError Ontology.add_data_property!(
            ontology,
            "height";
            domains=["Missing"],
        )
        @test_throws ArgumentError Ontology.add_individual!(
            ontology,
            "fern-1";
            types=["Missing"],
        )
        @test_throws ArgumentError Ontology.add_relationship!(
            ontology,
            "missing-individual",
            "unknown-property",
            "also-missing",
        )
        @test_throws ArgumentError Ontology.add_annotation!(
            ontology,
            Ontology.Annotation("", "value"),
        )
    end

    @testset "subclass cycles and validation of mutated references" begin
        ontology = Ontology.OntologyModel()
        Ontology.add_class!(ontology, "A")
        Ontology.add_class!(ontology, "B")
        Ontology.add_class!(ontology, "C")
        Ontology.add_class!(ontology, "D")
        Ontology.add_subclass!(ontology, "A", "B")
        Ontology.add_subclass!(ontology, "A", "C")
        Ontology.add_subclass!(ontology, "C", "D")
        @test_throws ArgumentError Ontology.add_subclass!(ontology, "D", "A")

        push!(ontology.classes["D"].superclasses, "A")
        push!(ontology.classes["B"].superclasses, "Unknown")
        issues = Ontology.validate(ontology)
        codes = getfield.(issues, :code)
        @test :subclass_cycle in codes
        @test :invalid_reference in codes
    end

    @testset "relationship reference validation and annotations" begin
        ontology = Ontology.OntologyModel()
        class = Ontology.add_class!(ontology, "Thing")
        property = Ontology.add_object_property!(ontology, "related-to")
        subject = Ontology.add_individual!(ontology, "subject"; types=["Thing"])
        object = Ontology.add_individual!(ontology, "object"; types=["Thing"])
        relationship = Ontology.add_relationship!(ontology, subject.id, property.id, object.id)
        Ontology.add_annotation!(relationship, "rdfs:comment", "An assertion.")

        push!(relationship.annotations, Ontology.Annotation("", "bad annotation"))
        issue_codes = getfield.(Ontology.validate(ontology), :code)
        @test :empty_annotation_property in issue_codes
        @test isempty(class.annotations)
    end

    @testset "deterministic template generation" begin
        function example_template(concept_metadata)
            return Template.IntermediateTemplate(
                concepts=[
                    Template.Concept(
                        "deep-learning";
                        name="Deep Learning",
                        description="A subfield of machine learning.",
                        parent="machine-learning",
                        metadata=concept_metadata,
                    ),
                    Template.Concept(
                        "ai";
                        name="AI",
                        labels=["artificial intelligence"],
                        description="The study of intelligent systems.",
                    ),
                    Template.Concept(
                        "machine-learning";
                        name="Machine Learning",
                        description="A field within artificial intelligence.",
                        parent="ai",
                    ),
                ],
                relationships=[
                    Template.ObjectRelationship(
                        "applied-to";
                        name="applied to",
                        source="deep-learning",
                        target="ai",
                        description="An application of deep learning.",
                        metadata=Dict("source" => "taxonomy"),
                    ),
                ],
                properties=[
                    Template.DataProperty(
                        "model-name";
                        name="model name",
                        value_type="xsd:string",
                        description="The name of a model.",
                        domain="machine-learning",
                    ),
                ],
                metadata=Dict(
                    "iri" => "https://example.org/ai",
                    "version" => "1.0",
                    "labels" => ["AI ontology"],
                    "source" => "example taxonomy",
                ),
            )
        end

        first_template = example_template(Dict(
            "z-source" => "taxonomy",
            "details" => Dict("second" => 2, "first" => 1),
        ))
        second_template = example_template(Dict(
            "details" => Dict("first" => 1, "second" => 2),
            "z-source" => "taxonomy",
        ))

        generated = Ontology.generate_ontology(first_template)
        repeated = Ontology.generate_ontology(second_template)

        @test ontology_snapshot(generated) == ontology_snapshot(repeated)
        @test generated.iri == "https://example.org/ai"
        @test generated.version == "1.0"
        @test generated.metadata == first_template.metadata
        @test generated.classes["ai"].labels == ["AI", "artificial intelligence"]
        @test generated.classes["ai"].definitions == ["The study of intelligent systems."]
        @test generated.classes["machine-learning"].superclasses == Set(["ai"])
        @test generated.classes["deep-learning"].superclasses == Set(["machine-learning"])
        @test generated.object_properties["applied-to"].domains == Set(["deep-learning"])
        @test generated.object_properties["applied-to"].ranges == Set(["ai"])
        @test generated.data_properties["model-name"].domains == Set(["machine-learning"])
        @test generated.data_properties["model-name"].ranges == Set(["xsd:string"])
        @test generated.classes["deep-learning"].annotations[1].property ==
            "urn:taxonomy-ontology-converter:metadata:details"
        @test isempty(generated.individuals)
        @test isempty(generated.relationships)
        @test Ontology.is_valid(generated)
    end

    @testset "generator rejects invalid input and output" begin
        invalid_template = Template.IntermediateTemplate(
            concepts=[Template.Concept("missing-label")],
        )
        @test_throws Ontology.TemplateValidationError Ontology.generate_ontology(invalid_template)

        template_with_empty_description = Template.IntermediateTemplate(
            concepts=[Template.Concept("concept"; name="Concept", description="")],
        )
        @test_throws Ontology.OntologyGenerationError Ontology.generate_ontology(
            template_with_empty_description,
        )
    end

    @testset "RDF/XML ontology serialization" begin
        ontology = Ontology.OntologyModel(
            iri="https://example.org/ecology",
            version="1.0",
            labels=["Ecology"],
            definitions=["An example ontology."],
            metadata=Dict("source" => "unit test"),
        )
        plant = Ontology.add_class!(
            ontology,
            "Plant species";
            labels=["plant", "species"],
            definitions=["A plant species."],
        )
        habitat = Ontology.add_class!(ontology, "Habitat"; labels=["habitat"])
        Ontology.add_subclass!(ontology, "Plant species", "Habitat")
        grows_in = Ontology.add_object_property!(
            ontology,
            "grows-in";
            labels=["grows in"],
            domains=["Plant species"],
            ranges=["Habitat"],
        )
        Ontology.add_data_property!(
            ontology,
            "height";
            labels=["height"],
            domains=["Plant species"],
            ranges=["xsd:decimal"],
        )
        Ontology.add_data_property!(
            ontology,
            "typical-lifespan";
            domains=["Plant species"],
            ranges=["number"],
        )
        oak = Ontology.add_individual!(
            ontology,
            "oak-1";
            types=["Plant species"],
            labels=["Oak"],
        )
        forest = Ontology.add_individual!(ontology, "forest-1"; types=["Habitat"])
        relationship = Ontology.add_relationship!(
            ontology,
            oak.id,
            grows_in.id,
            forest.id,
        )
        Ontology.add_annotation!(plant, "dcterms:source", "field guide"; language="en")
        Ontology.add_annotation!(relationship, "rdfs:comment", "Observed in the field.")

        mktempdir() do directory
            path = joinpath(directory, "nested", "example.owl")
            second_path = joinpath(directory, "second.owl")
            @test Ontology.save_ontology(ontology, path) == path
            Ontology.save_ontology(ontology, second_path)
            @test read(path, String) == read(second_path, String)

            graph = open(path, "r") do io
                read(io, :rdfxml, RDF.Graph)
            end
            base = "https://example.org/ecology#"
            rdf_type = RDF.IRI("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")
            rdf_label = RDF.IRI("http://www.w3.org/2000/01/rdf-schema#label")
            rdfs_subclass = RDF.IRI("http://www.w3.org/2000/01/rdf-schema#subClassOf")
            rdfs_domain = RDF.IRI("http://www.w3.org/2000/01/rdf-schema#domain")
            rdfs_range = RDF.IRI("http://www.w3.org/2000/01/rdf-schema#range")
            owl_class = RDF.IRI("http://www.w3.org/2002/07/owl#Class")
            owl_object_property = RDF.IRI("http://www.w3.org/2002/07/owl#ObjectProperty")
            owl_ontology = RDF.IRI("http://www.w3.org/2002/07/owl#Ontology")
            owl_version_info = RDF.IRI("http://www.w3.org/2002/07/owl#versionInfo")
            xsd_decimal = RDF.IRI("http://www.w3.org/2001/XMLSchema#decimal")
            ontology_iri = RDF.IRI("https://example.org/ecology")
            plant_iri = RDF.IRI(base * "Plant%20species")
            habitat_iri = RDF.IRI(base * "Habitat")
            property_iri = RDF.IRI(base * "grows-in")
            oak_iri = RDF.IRI(base * "oak-1")
            forest_iri = RDF.IRI(base * "forest-1")

            @test RDF.Triple(ontology_iri, rdf_type, owl_ontology) in graph
            @test RDF.Triple(ontology_iri, owl_version_info, RDF.Literal("1.0")) in graph
            @test RDF.Triple(plant_iri, rdf_type, owl_class) in graph
            @test RDF.Triple(plant_iri, rdfs_subclass, habitat_iri) in graph
            @test RDF.Triple(property_iri, rdf_type, owl_object_property) in graph
            @test RDF.Triple(
                RDF.IRI(base * "height"),
                rdfs_domain,
                plant_iri,
            ) in graph
            @test RDF.Triple(
                property_iri,
                rdfs_range,
                habitat_iri,
            ) in graph
            @test RDF.Triple(
                RDF.IRI(base * "height"),
                rdfs_range,
                xsd_decimal,
            ) in graph
            @test RDF.Triple(
                RDF.IRI(base * "typical-lifespan"),
                rdfs_range,
                xsd_decimal,
            ) in graph
            @test RDF.Triple(
                plant_iri,
                rdf_label,
                RDF.Literal("plant"),
            ) in graph
            @test RDF.Triple(oak_iri, property_iri, forest_iri) in graph
            @test RDF.Triple(
                plant_iri,
                RDF.IRI("http://purl.org/dc/terms/source"),
                RDF.Literal("field guide"; lang="en"),
            ) in graph
            @test any(
                triple -> triple.predicate == RDF.IRI(
                    "urn:taxonomy-ontology-converter:metadata:source",
                ),
                graph,
            )

            axiom_nodes = [
                triple.subject for triple in graph
                if triple.predicate == rdf_type && triple.object ==
                    RDF.IRI("http://www.w3.org/2002/07/owl#Axiom")
            ]
            @test length(axiom_nodes) == 1
            @test RDF.Triple(
                only(axiom_nodes),
                RDF.IRI("http://www.w3.org/2002/07/owl#annotatedSource"),
                oak_iri,
            ) in graph
            @test RDF.Triple(
                only(axiom_nodes),
                RDF.IRI("http://www.w3.org/2000/01/rdf-schema#comment"),
                RDF.Literal("Observed in the field."),
            ) in graph
        end
    end

    @testset "serialization IRI requirements" begin
        ontology_without_iri = Ontology.OntologyModel()
        Ontology.add_class!(ontology_without_iri, "https://example.org/AbsoluteClass")
        invalid_local = Ontology.OntologyModel()
        Ontology.add_class!(invalid_local, "LocalClass")

        mktempdir() do directory
            path = joinpath(directory, "anonymous.owl")
            @test Ontology.save_ontology(ontology_without_iri, path) == path
            @test_throws ArgumentError Ontology.save_ontology(
                invalid_local,
                joinpath(directory, "invalid.owl"),
            )
        end
    end
end
