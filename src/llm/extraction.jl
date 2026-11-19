export MockLLM, ExtractionResponseError, ExtractionValidationError, extract_template

"""
A deterministic LLM implementation for tests and offline examples.
"""
mutable struct MockLLM <: AbstractLLM
    response::String
    prompts::Vector{String}
end

MockLLM(response::AbstractString) = MockLLM(String(response), String[])

function complete(llm::MockLLM, prompt::AbstractString)
    push!(llm.prompts, String(prompt))
    return llm.response
end

"""
Raised when the model response cannot be parsed into an intermediate template.
"""
struct ExtractionResponseError <: Exception
    cause::Exception
end

function Base.showerror(io::IO, error::ExtractionResponseError)
    print(io, "LLM response is not a valid intermediate-template JSON document: ")
    showerror(io, error.cause)
end

"""
Raised when the parsed intermediate template fails Julia-side validation.
"""
struct ExtractionValidationError <: Exception
    issues::Vector{ValidationIssue}
end

function Base.showerror(io::IO, error::ExtractionValidationError)
    print(io, "LLM extraction produced an invalid intermediate template:")
    for issue in error.issues
        print(io, "\n- ", issue.path, " [", issue.code, "]: ", issue.message)
    end
end

"""
    extract_template(llm::AbstractLLM, taxonomy)

Prompt an LLM to extract a JSON intermediate template, deserialize the response,
and return the template only if Julia-side validation succeeds.
"""
function extract_template(llm::AbstractLLM, taxonomy)
    prompt = build_extraction_prompt(taxonomy)
    response = complete(llm, prompt)
    response isa AbstractString ||
        throw(ArgumentError("complete must return a string response, got $(typeof(response))"))

    template = try
        from_json(response)
    catch error
        throw(ExtractionResponseError(error))
    end

    issues = validate(template)
    isempty(issues) || throw(ExtractionValidationError(issues))
    return template::IntermediateTemplate
end
