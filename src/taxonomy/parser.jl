using JSON

export ParsedTaxonomy, TaxonomyParseError, parse_taxonomy

struct ParsedTaxonomy
    source_path::String
    format::Symbol
    content::String
end

struct TaxonomyParseError <: Exception
    source_path::String
    cause::Exception
end

function Base.showerror(io::IO, error::TaxonomyParseError)
    print(io, "could not parse taxonomy '", error.source_path, "': ")
    showerror(io, error.cause)
end

"""
    parse_taxonomy(document::TaxonomyDocument) -> ParsedTaxonomy

Normalize line endings and validate JSON syntax when the input is a JSON file.
Other supported documents are preserved as text for LLM-assisted extraction.
"""
function parse_taxonomy(document::TaxonomyDocument)
    content = replace(document.content, "\r\n" => "\n", "\r" => "\n")
    if document.format == :json && !isempty(strip(content))
        try
            JSON.parse(content)
        catch error
            error isa InterruptException && rethrow()
            throw(TaxonomyParseError(document.path, error))
        end
    end
    return ParsedTaxonomy(document.path, document.format, content)
end
