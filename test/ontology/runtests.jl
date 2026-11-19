using Test

const Ontology = TaxonomyOntologyConverter.Ontology

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
end
