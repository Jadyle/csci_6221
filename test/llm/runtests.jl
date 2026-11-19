using Test

const LLM = TaxonomyOntologyConverter.LLM
const Template = TaxonomyOntologyConverter.Template

struct TestTaxonomy
    text::String
end

struct UnimplementedLLM <: LLM.AbstractLLM end

TaxonomyOntologyConverter.LLM.taxonomy_text(taxonomy::TestTaxonomy) = taxonomy.text

@testset "LLM extraction pipeline" begin
    response = """
    {
      "schema_version": "1.0",
      "concepts": [
        {
          "id": "tree",
          "name": "Tree",
          "labels": ["tree"],
          "description": "A woody perennial plant.",
          "parent": null,
          "metadata": {"source": "taxonomy"}
        },
        {
          "id": "forest",
          "name": "Forest",
          "labels": ["forest"],
          "description": "An area dominated by trees.",
          "parent": null,
          "metadata": {}
        }
      ],
      "relationships": [
        {
          "id": "grows-in",
          "name": "grows in",
          "source": "tree",
          "target": "forest",
          "description": null,
          "metadata": {}
        }
      ],
      "properties": [
        {
          "id": "height",
          "name": "height",
          "type": "number",
          "description": "Typical height.",
          "domain": "tree",
          "metadata": {}
        }
      ],
      "metadata": {"source": "mock"}
    }
    """
    mock = LLM.MockLLM(response)
    taxonomy = TestTaxonomy("A tree is a woody perennial plant. Trees grow in forests.")

    template = LLM.extract_template(mock, taxonomy)

    @test Template.is_valid(template)
    @test first(template.concepts).id == "tree"
    @test length(template.concepts) == 2
    @test only(template.relationships).target == "forest"
    @test only(template.properties).value_type == "number"
    @test length(mock.prompts) == 1
    @test occursin("JSON", only(mock.prompts))
    @test occursin("concepts/classes", only(mock.prompts))
    @test occursin("parent-child", only(mock.prompts))
    @test occursin("properties", only(mock.prompts))
    @test occursin("Taxonomy input (JSON data)", only(mock.prompts))
    @test occursin("A tree is a woody perennial plant.", only(mock.prompts))
    @test occursin("no Markdown, code fence, commentary, or OWL", only(mock.prompts))
end

@testset "LLM extraction rejects invalid output" begin
    invalid_template = """{"concepts":[{"id":"unknown"}]}"""
    mock = LLM.MockLLM(invalid_template)

    error = try
        LLM.extract_template(mock, "A taxonomy.")
        nothing
    catch error
        error
    end

    @test error isa LLM.ExtractionValidationError
    @test :missing_label in getfield.(error.issues, :code)
end

@testset "LLM provider and taxonomy interfaces" begin
    @test LLM.taxonomy_text("raw taxonomy") == "raw taxonomy"
    @test_throws ArgumentError LLM.taxonomy_text(123)

    @test_throws ArgumentError LLM.complete(UnimplementedLLM(), "prompt")
end

@testset "LLM extraction rejects malformed JSON" begin
    @test_throws LLM.ExtractionResponseError LLM.extract_template(
        LLM.MockLLM("not JSON"),
        "A taxonomy.",
    )
end
