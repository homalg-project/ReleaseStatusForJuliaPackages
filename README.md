# ReleaseStatusForJuliaPackages

Automated [Shields endpoint](https://shields.io/badges/endpoint-badge) data for Julia packages.

The hourly GitHub Actions workflow checks every immediate subdirectory containing a
`Project.toml` in these monorepos:

- [CAP_project.jl](https://github.com/homalg-project/CAP_project.jl)
- [CategoricalTowers.jl](https://github.com/homalg-project/CategoricalTowers.jl)
- [HigherHomologicalAlgebra.jl](https://github.com/homalg-project/HigherHomologicalAlgebra.jl)

For each package, it compares the source version against the latest available release
in Julia's General registry and writes badge data to
`<monorepo>/badges/<package>.json`.
