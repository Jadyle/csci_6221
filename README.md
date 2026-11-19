# TaxonomyOntologyConverter

TaxonomyOntologyConverter is a Julia package for research into converting
taxonomies into ontologies. This initial package provides a minimal loading
and testing foundation; conversion functionality is not implemented yet.

## Run the tests

From the package root, start Julia and run:

```julia
] test
```

Alternatively, run the tests without entering the package manager:

```sh
julia --project -e 'using Pkg; Pkg.test()'
```

## Load the package

From the package root, start Julia with the project environment:

```sh
julia --project
```

Then load and try the package:

```julia
using TaxonomyOntologyConverter
hello()
```
