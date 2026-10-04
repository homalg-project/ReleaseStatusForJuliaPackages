#!/usr/bin/env julia
#
# Checks every Julia package in the configured monorepos against the latest
# non-yanked General-registry version and writes Shields endpoint JSON files.

import Pkg
using TOML

const MONOREPOS = [
    "CAP_project.jl",
    "CategoricalTowers.jl",
    "HigherHomologicalAlgebra.jl",
]

const STDLIBS = Set([
    "ArgTools", "Artifacts", "Base64", "Dates", "DelimitedFiles", "Distributed",
    "Downloads", "FileWatching", "Future", "InteractiveUtils", "LazyArtifacts",
    "LibCURL", "LibGit2", "Libdl", "LinearAlgebra", "Logging", "Markdown", "Mmap",
    "NetworkOptions", "Pkg", "Printf", "Profile", "Random", "REPL", "SHA",
    "Serialization", "SharedArrays", "Sockets", "SparseArrays", "Statistics",
    "SuiteSparse", "TOML", "Tar", "Test", "UUIDs", "Unicode",
])

function package_names(monorepo_path::AbstractString)
    packages = String[]
    for name in readdir(monorepo_path)
        isfile(joinpath(monorepo_path, name, "Project.toml")) && push!(packages, name)
    end
    return sort!(packages)
end

function local_version(monorepo_path::AbstractString, package::AbstractString)
    project = TOML.parsefile(joinpath(monorepo_path, package, "Project.toml"))
    return VersionNumber(project["version"])
end

function registered_version_info(registry, package_entry)
    registry_info = Pkg.Registry.registry_info
    return applicable(registry_info, package_entry) ?
        registry_info(package_entry).version_info : registry_info(registry, package_entry).version_info
end

function latest_registered_version(registry, package::AbstractString)
    package_entry = nothing
    for entry in values(registry.pkgs)
        if entry.name == package
            package_entry = entry
            break
        end
    end
    package_entry === nothing && return nothing

    version_info = registered_version_info(registry, package_entry)
    non_yanked = [version for (version, info) in version_info if !info.yanked]
    return isempty(non_yanked) ? nothing : maximum(non_yanked)
end

function latest_compatible_version(registry, package::AbstractString, compatibility)
    package_entry = nothing
    for entry in values(registry.pkgs)
        if entry.name == package
            package_entry = entry
            break
        end
    end
    package_entry === nothing && return nothing

    version_spec = compatibility === nothing ? nothing : Pkg.Types.semver_spec(compatibility)
    version_info = registered_version_info(registry, package_entry)
    compatible = [
        version for (version, info) in version_info
        if !info.yanked && (version_spec === nothing || version in version_spec)
    ]
    return isempty(compatible) ? nothing : maximum(compatible)
end

function badge_json(; label::AbstractString, message::AbstractString, color::AbstractString)
    escape(value) = replace(value, "\"" => "\\\"")
    return "{\"schemaVersion\":1,\"label\":\"$(escape(label))\",\"message\":\"$(escape(message))\",\"color\":\"$(escape(color))\"}\n"
end

function status_badge(monorepo_path::AbstractString, registry, package::AbstractString)
    local_v = local_version(monorepo_path, package)
    latest_v = latest_registered_version(registry, package)

    if latest_v === nothing
        return badge_json(label = "release", message = "v$(local_v) never registered", color = "lightgrey")
    elseif local_v == latest_v
        return badge_json(label = "release", message = "v$(local_v) released", color = "brightgreen")
    elseif local_v > latest_v
        return badge_json(label = "release", message = "v$(local_v) NOT released (latest: v$(latest_v))", color = "orange")
    else
        return badge_json(label = "release", message = "v$(local_v) (registry has v$(latest_v))", color = "red")
    end
end

function dependency_badge(registry, dependency::AbstractString, compatibility)
    dependency in STDLIBS && return badge_json(
        label = "dependency",
        message = "Julia standard library",
        color = "brightgreen",
    )

    latest_v = latest_compatible_version(registry, dependency, compatibility)
    if latest_v === nothing
        requirement = compatibility === nothing ? "" : " matching $(compatibility)"
        return badge_json(
            label = "dependency",
            message = "no released version$(requirement)",
            color = "red",
        )
    end

    return badge_json(
        label = "dependency",
        message = "v$(latest_v) available",
        color = "brightgreen",
    )
end

function remove_stale_directories(output_root::AbstractString, expected_directories)
    for entry in readdir(output_root)
        path = joinpath(output_root, entry)
        isdir(path) && !(entry in expected_directories) && rm(path; recursive = true)
    end
end

function write_badges(sources_root::AbstractString, registry, monorepo::AbstractString)
    monorepo_path = joinpath(sources_root, monorepo)
    packages = package_names(monorepo_path)
    output_root = joinpath(@__DIR__, "..", monorepo)
    mkpath(output_root)
    remove_stale_directories(output_root, Set(packages))

    for package in packages
        project = TOML.parsefile(joinpath(monorepo_path, package, "Project.toml"))
        package_dir = joinpath(output_root, package)
        dependencies_dir = joinpath(package_dir, "dependencies")
        mkpath(dependencies_dir)

        release_path = joinpath(package_dir, "release.json")
        write(release_path, status_badge(monorepo_path, registry, package))
        println("Wrote $(release_path)")

        dependencies = sort!(collect(keys(get(project, "deps", Dict()))))
        compatibility = get(project, "compat", Dict())
        expected_files = Set("$(dependency).json" for dependency in dependencies)
        for file in readdir(dependencies_dir)
            endswith(file, ".json") && !(file in expected_files) && rm(joinpath(dependencies_dir, file))
        end

        for dependency in dependencies
            path = joinpath(dependencies_dir, "$(dependency).json")
            write(path, dependency_badge(registry, dependency, get(compatibility, dependency, nothing)))
            println("Wrote $(path)")
        end
    end
end

function main()
    sources_root = isempty(ARGS) ? joinpath(@__DIR__, "..", "sources") : only(ARGS)
    isempty(Pkg.Registry.reachable_registries()) && Pkg.Registry.add("General")
    Pkg.Registry.update()
    general = only(filter(registry -> registry.name == "General", Pkg.Registry.reachable_registries()))

    for monorepo in MONOREPOS
        write_badges(sources_root, general, monorepo)
    end
end

main()
