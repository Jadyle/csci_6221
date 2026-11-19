export TaxonomyDocument, load_taxonomy

struct TaxonomyDocument
    path::String
    content::String
    format::Symbol
end

const _TAXONOMY_FORMATS = Dict(
    ".json" => :json,
    ".csv" => :csv,
    ".html" => :html,
    ".htm" => :html,
    ".md" => :markdown,
    ".markdown" => :markdown,
    ".xml" => :xml,
    ".txt" => :text,
)

function _taxonomy_format(path::AbstractString)
    extension = lowercase(splitext(path)[2])
    return get(_TAXONOMY_FORMATS, extension, :text)
end

"""
    load_taxonomy(path) -> TaxonomyDocument

Read taxonomy input as text while recording its source path and detected
format. Format-specific interpretation is handled by `parse_taxonomy`.
"""
function load_taxonomy(path::AbstractString)
    source_path = String(path)
    isempty(strip(source_path)) &&
        throw(ArgumentError("taxonomy input path must not be empty"))
    isfile(source_path) ||
        throw(ArgumentError("taxonomy input file does not exist: '$source_path'"))
    content = read(source_path, String)
    return TaxonomyDocument(source_path, content, _taxonomy_format(source_path))
end
