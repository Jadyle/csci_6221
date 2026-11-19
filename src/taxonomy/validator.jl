export TaxonomyValidationIssue, TaxonomyValidationError, validate_taxonomy

struct TaxonomyValidationIssue
    code::Symbol
    path::String
    message::String
end

struct TaxonomyValidationError <: Exception
    issues::Vector{TaxonomyValidationIssue}
end

function Base.showerror(io::IO, error::TaxonomyValidationError)
    print(io, "taxonomy input failed validation:")
    for issue in error.issues
        print(io, "\n- ", issue.path, " [", issue.code, "]: ", issue.message)
    end
end

function validate_taxonomy(taxonomy::ParsedTaxonomy)
    issues = TaxonomyValidationIssue[]
    isempty(strip(taxonomy.source_path)) && push!(issues, TaxonomyValidationIssue(
        :missing_source,
        "source_path",
        "taxonomy source path must not be empty",
    ))
    isempty(strip(taxonomy.content)) && push!(issues, TaxonomyValidationIssue(
        :empty_content,
        "content",
        "taxonomy input must not be empty",
    ))
    taxonomy.format in (:json, :csv, :html, :markdown, :xml, :text) ||
        push!(issues, TaxonomyValidationIssue(
            :unsupported_format,
            "format",
            "unsupported taxonomy format '$(taxonomy.format)'",
        ))
    return issues
end
