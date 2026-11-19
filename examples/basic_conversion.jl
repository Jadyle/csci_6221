using TaxonomyOntologyConverter

const ProjectRoot = normpath(joinpath(@__DIR__, ".."))
const LLM = TaxonomyOntologyConverter.LLM

taxonomy_path = joinpath(ProjectRoot, "data", "input", "example-taxonomy.txt")
response_path = joinpath(@__DIR__, "mock-extraction.json")
output_path = joinpath(ProjectRoot, "data", "output", "example-pipeline.owl")

mock_llm = LLM.MockLLM(read(response_path, String))
result = convert_taxonomy(
    taxonomy_path;
    llm=mock_llm,
    output_path=output_path,
)

println("OWL ontology written to: ", result.output_path)
