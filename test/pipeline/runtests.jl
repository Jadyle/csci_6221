using Test
using RDF

const Pipeline = TaxonomyOntologyConverter
const LLM = TaxonomyOntologyConverter.LLM

@testset "End-to-end taxonomy-to-ontology conversion" begin
    extraction_response = """
    {
      "schema_version": "1.0",
      "concepts": [
        {
          "id": "ai",
          "name": "Artificial Intelligence",
          "labels": ["AI"],
          "description": "The study of intelligent systems.",
          "parent": null,
          "metadata": {}
        },
        {
          "id": "machine-learning",
          "name": "Machine Learning",
          "labels": [],
          "description": "A field within artificial intelligence.",
          "parent": "ai",
          "metadata": {}
        },
        {
          "id": "deep-learning",
          "name": "Deep Learning",
          "labels": [],
          "description": "A subfield of machine learning.",
          "parent": "machine-learning",
          "metadata": {}
        }
      ],
      "relationships": [],
      "properties": [],
      "metadata": {
        "iri": "https://example.org/pipeline-ai",
        "version": "1.0"
      }
    }
    """
    llm = LLM.MockLLM(extraction_response)

    mktempdir() do directory
        output_path = joinpath(directory, "nested", "ontology.owl")
        input_path = joinpath(dirname(@__DIR__), "..", "data", "input", "example-taxonomy.txt")
        result = Pipeline.convert_taxonomy(
            input_path;
            llm=llm,
            output_path=output_path,
        )

        @test result isa Pipeline.ConversionResult
        @test result.taxonomy.format == :text
        @test length(result.template.concepts) == 3
        @test result.ontology.classes["deep-learning"].superclasses ==
            Set(["machine-learning"])
        @test result.output_path == output_path
        @test isfile(output_path)
        @test occursin("Input format: text", only(llm.prompts))

        graph = open(output_path, "r") do io
            read(io, :rdfxml, RDF.Graph)
        end
        base = "https://example.org/pipeline-ai#"
        @test RDF.Triple(
            RDF.IRI(base * "deep-learning"),
            RDF.IRI("http://www.w3.org/2000/01/rdf-schema#subClassOf"),
            RDF.IRI(base * "machine-learning"),
        ) in graph
    end
end

@testset "Pipeline reports stage-specific failures" begin
    taxonomy_path = joinpath(dirname(@__DIR__), "..", "data", "input", "example-taxonomy.txt")
    missing_provider = try
        Pipeline.convert_taxonomy(taxonomy_path)
        nothing
    catch error
        error
    end
    @test missing_provider isa Pipeline.ConversionError
    @test missing_provider.stage == :llm_extraction
    @test occursin("LLM provider is required", sprint(showerror, missing_provider))

    invalid_template_llm = LLM.MockLLM(
        """{"schema_version":"1.0","concepts":[{"id":"missing-label"}],"relationships":[],"properties":[],"metadata":{}}""",
    )
    invalid_template = try
        Pipeline.convert_taxonomy(taxonomy_path; llm=invalid_template_llm)
        nothing
    catch error
        error
    end
    @test invalid_template isa Pipeline.ConversionError
    @test invalid_template.stage == :template_validation
    @test occursin("concept must have a name", sprint(showerror, invalid_template))

    malformed_template_llm = LLM.MockLLM("{bad-json")
    malformed_template = try
        Pipeline.convert_taxonomy(taxonomy_path; llm=malformed_template_llm)
        nothing
    catch error
        error
    end
    @test malformed_template isa Pipeline.ConversionError
    @test malformed_template.stage == :llm_extraction
    @test occursin("not a valid intermediate-template JSON", sprint(showerror, malformed_template))

    mktempdir() do directory
        invalid_json_path = joinpath(directory, "taxonomy.json")
        write(invalid_json_path, "{invalid")
        parse_error_llm = LLM.MockLLM("{}")
        parse_error = try
            Pipeline.convert_taxonomy(invalid_json_path; llm=parse_error_llm)
            nothing
        catch error
            error
        end
        @test parse_error isa Pipeline.ConversionError
        @test parse_error.stage == :taxonomy_parsing
        @test isempty(parse_error_llm.prompts)
    end
end
