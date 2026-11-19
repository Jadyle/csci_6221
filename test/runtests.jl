using TaxonomyOntologyConverter
using Test

@testset "TaxonomyOntologyConverter.jl" begin
    @test hello() == "Hello from TaxonomyOntologyConverter!"
    @test TaxonomyOntologyConverter.Taxonomy isa Module
    @test TaxonomyOntologyConverter.Template isa Module
    @test TaxonomyOntologyConverter.LLM isa Module
    @test TaxonomyOntologyConverter.Ontology isa Module
    @test TaxonomyOntologyConverter.Enrichment isa Module
    @test TaxonomyOntologyConverter.Utils isa Module
end

include("template/runtests.jl")
include("taxonomy/runtests.jl")
include("llm/runtests.jl")
include("ontology/runtests.jl")
include("enrichment/runtests.jl")
include("pipeline/runtests.jl")
