using Test

const IR = TaxonomyOntologyConverter.Template

@testset "Intermediate template" begin
    @testset "concept validation" begin
        concept = IR.Concept(
            "animal";
            name="Animal",
            labels=["animal", "Animal"],
            description="A living organism.",
            metadata=Dict("source" => "example"),
        )
        @test IR.is_valid(concept)
        @test isempty(IR.validate(concept))

        invalid = IR.Concept(""; name=" ")
        issues = IR.validate(invalid)
        @test :missing_label in getfield.(issues, :code)
        @test :empty_required_field in getfield.(issues, :code)
    end

    @testset "relationships and properties" begin
        relationship = IR.ObjectRelationship(
            "inhabits";
            name="inhabits",
            source="animal",
            target="habitat",
            description="The habitat used by an animal.",
        )
        property = IR.DataProperty(
            "body-mass";
            name="body mass",
            value_type="number",
            domain="animal",
            description="Mass of an animal.",
        )
        @test IR.is_valid(relationship)
        @test IR.is_valid(property)

        incomplete_property = IR.DataProperty("unknown-property"; name="unknown")
        @test :missing_required_field in getfield.(IR.validate(incomplete_property), :code)
    end

    @testset "serialization round trip" begin
        template = IR.IntermediateTemplate(
            concepts=[
                IR.Concept("animal"; name="Animal", labels=["animal"]),
                IR.Concept("habitat"; name="Habitat", parent="animal"),
            ],
            relationships=[
                IR.ObjectRelationship(
                    "inhabits";
                    name="inhabits",
                    source="animal",
                    target="habitat",
                ),
            ],
            properties=[
                IR.DataProperty(
                    "body-mass";
                    name="body mass",
                    value_type="number",
                    domain="animal",
                    metadata=Dict("unit" => "kg"),
                ),
            ],
            metadata=Dict("source" => "unit test"),
        )

        json = IR.to_json(template)
        restored = IR.from_json(json)
        @test IR.to_dict(restored) == IR.to_dict(template)
        @test IR.is_valid(restored)

        partial = IR.from_json("""{"concepts":[{"id":"partial"}]}""")
        @test isnothing(only(partial.concepts).name)
        @test isempty(only(partial.concepts).labels)
        @test !IR.is_valid(partial)
    end

    @testset "example JSON data" begin
        example_path = joinpath(@__DIR__, "../../data/intermediate/example-template.json")
        template = IR.from_json(read(example_path, String))
        @test IR.is_valid(template)
        @test length(template.concepts) == 2
        @test length(template.relationships) == 1
        @test length(template.properties) == 1
    end

    @testset "duplicate identifiers and invalid references" begin
        template = IR.IntermediateTemplate(
            concepts=[
                IR.Concept("same"; name="First"),
                IR.Concept("same"; name="Second", parent="missing"),
            ],
            relationships=[
                IR.ObjectRelationship(
                    "relation";
                    name="related to",
                    source="missing",
                    target="same",
                ),
            ],
            properties=[
                IR.DataProperty(
                    "property";
                    name="value",
                    value_type="string",
                    domain="missing",
                ),
            ],
        )

        issues = IR.validate(template)
        codes = getfield.(issues, :code)
        @test :duplicate_identifier in codes
        @test count(==(:invalid_reference), codes) == 3
    end

    @testset "parent hierarchy cycles" begin
        template = IR.IntermediateTemplate(concepts=[
            IR.Concept("first"; name="First", parent="second"),
            IR.Concept("second"; name="Second", parent="first"),
        ])
        @test :parent_cycle in getfield.(IR.validate(template), :code)
    end
end
