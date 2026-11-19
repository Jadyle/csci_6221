using Test

const Taxonomy = TaxonomyOntologyConverter.Taxonomy

@testset "Taxonomy input" begin
    @testset "loading and format detection" begin
        mktempdir() do directory
            text_path = joinpath(directory, "input.TXT")
            write(text_path, "Root\n  Child\r\n")

            document = Taxonomy.load_taxonomy(text_path)
            @test document.path == text_path
            @test document.format == :text
            @test document.content == "Root\n  Child\r\n"

            json_path = joinpath(directory, "input.json")
            write(json_path, """{"concepts": []}""")
            @test Taxonomy.load_taxonomy(json_path).format == :json

            @test_throws ArgumentError Taxonomy.load_taxonomy("")
            @test_throws ArgumentError Taxonomy.load_taxonomy(joinpath(directory, "missing.txt"))
        end
    end

    @testset "parsing and validation" begin
        parsed = Taxonomy.parse_taxonomy(
            Taxonomy.TaxonomyDocument("taxonomy.txt", "Root\r\n  Child\r", :text),
        )
        @test parsed.content == "Root\n  Child\n"
        @test isempty(Taxonomy.validate_taxonomy(parsed))

        valid_json = Taxonomy.parse_taxonomy(
            Taxonomy.TaxonomyDocument("taxonomy.json", """{"concepts": []}""", :json),
        )
        @test valid_json.format == :json
        @test isempty(Taxonomy.validate_taxonomy(valid_json))

        @test_throws Taxonomy.TaxonomyParseError Taxonomy.parse_taxonomy(
            Taxonomy.TaxonomyDocument("broken.json", "{", :json),
        )

        empty_taxonomy = Taxonomy.ParsedTaxonomy("empty.txt", :text, " \n")
        @test :empty_content in getfield.(Taxonomy.validate_taxonomy(empty_taxonomy), :code)

        unsupported_taxonomy = Taxonomy.ParsedTaxonomy("input.bin", :binary, "content")
        @test :unsupported_format in getfield.(Taxonomy.validate_taxonomy(unsupported_taxonomy), :code)
    end
end
