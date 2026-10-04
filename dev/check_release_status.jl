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

function write_badges(sources_root::AbstractString, registry, monorepo::AbstractString)
    monorepo_path = joinpath(sources_root, monorepo)
    packages = package_names(monorepo_path)
    badges_dir = joinpath(@__DIR__, "..", monorepo, "badges")
    mkpath(badges_dir)

    expected_files = Set("$(package).json" for package in packages)
    for file in readdir(badges_dir)
        endswith(file, ".json") && !(file in expected_files) && rm(joinpath(badges_dir, file))
    end

    for package in packages
        path = joinpath(badges_dir, "$(package).json")
        write(path, status_badge(monorepo_path, registry, package))
        println("Wrote $(path)")
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