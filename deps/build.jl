using BinaryProvider
using CUDAdrv

#=

This script generates deps/deps.jl with information about the CUDA toolkit:

- nvdisasm
- ptxas
- libdevice
- libcudadevrt
- toolkit_version
- use_binarybuilder (see below)

There are two major scenario's on how these variables are populated.


1) CUDA was downloaded at build-time using BinaryBuilder

This depends on a couple of things:

- JULIA_CUDA_USE_BINARYBUILDER=true (default)
- CUDAdrv.jl is functional (i.e. we have CUDA at build time)
- supported platform and CUDA version

In that case, we will download CUDA, set `use_binarybuilder` to `true`, and assign concrete
values to each of the other variables.


2) CUDA will be discovered at run-time

If the above failed, we will expect CUDA to be readily available (i.e., on PATH or
LD_LIBRARY_PATH) at run time by assigning generic values to the variables in `deps.jl`.

Exceptions to this are FileProducts, which cannot be found in PATH or LD_LIBRARY_PATH;
`libcudadevrt` and `libdevice` will be set to `nothing` instead and populated during
`__init__`. Similarly, `toolkit_version` will be parsed from the output of `ptxas` during
module initialization.

=#

# Parse some basic command-line arguments
const verbose = "--verbose" in ARGS
const prefix = Prefix(get([a for a in ARGS if a != "--verbose"], 1, joinpath(@__DIR__, "usr")))

# online sources we can use
const bin_prefix = "https://github.com/JuliaGPU/CUDABuilder/releases/download/v0.1.4"
const resources = Dict(
    v"9.0" =>
        Dict(
            MacOS(:x86_64) => ("$bin_prefix/CUDA.v9.0.176-0.1.4.x86_64-apple-darwin14.tar.gz", "b780b67dbdbe445e20c1b8903a9b67b9a475fd61cb4b9dab211b47c0f0832be8"),
            Linux(:x86_64, libc=:glibc) => ("$bin_prefix/CUDA.v9.0.176-0.1.4.x86_64-linux-gnu.tar.gz", "61710504dc0ad4f664a300128c3cbede136d8ca8dc0407c2d1fe33a9f79b890c"),
            Windows(:x86_64) => ("$bin_prefix/CUDA.v9.0.176-0.1.4.x86_64-w64-mingw32.tar.gz", "2fb1abe3b682a4b5ddccab052e8e33c873d710b20bdfe9bb543b128b3990b927"),
        ),
    v"9.2" =>
        Dict(
            MacOS(:x86_64) => ("$bin_prefix/CUDA.v9.2.148-0.1.4.x86_64-apple-darwin14.tar.gz", "052ec15d79ce010a10baa4f2b4fac1247e7d1e157977654dd9468db5fbbdcd57"),
            Linux(:x86_64, libc=:glibc) => ("$bin_prefix/CUDA.v9.2.148-0.1.4.x86_64-linux-gnu.tar.gz", "e8ccab79aa2773bf058edb8ad3b9bf2d04690eff6322609779ab1815f9cb610c"),
            Windows(:x86_64) => ("$bin_prefix/CUDA.v9.2.148-0.1.4.x86_64-w64-mingw32.tar.gz", "0b861a7d4a9a3f11c40716d6816b561eb6aa1a90269c3d54a225e23aff009736"),
        ),
    v"10.0" =>
        Dict(
            MacOS(:x86_64) => ("$bin_prefix/CUDA.v10.0.130-0.1.4.x86_64-apple-darwin14.tar.gz", "cc5107708cefb4876d75a56a7cd8e19b76104965bd60431e7eb3fe6995bf914f"),
            Linux(:x86_64, libc=:glibc) => ("$bin_prefix/CUDA.v10.0.130-0.1.4.x86_64-linux-gnu.tar.gz", "c5e88d4575e4742fda1c40e6ba86f48ea4b217b174abaf6a47f93f3410673d52"),
            Windows(:x86_64) => ("$bin_prefix/CUDA.v10.0.130-0.1.4.x86_64-w64-mingw32.tar.gz", "f77b30f31c4fa93209effd7302ff7642006dcdc2a6babe52a37101df0bac8300"),
        ),
    v"10.1" =>
        Dict(
            MacOS(:x86_64) => ("$bin_prefix/CUDA.v10.1.243-0.1.4.x86_64-apple-darwin14.tar.gz", "643729587d829001cde2a7692bab3c028f538773c6ea2fa530a1000a45a3bd3a"),
            Linux(:x86_64, libc=:glibc) => ("$bin_prefix/CUDA.v10.1.243-0.1.4.x86_64-linux-gnu.tar.gz", "45cfb9b735b0ff130e611e9ffdfa11613001015e2180bbe11491d6dae7d180cb"),
            Windows(:x86_64) => ("$bin_prefix/CUDA.v10.1.243-0.1.4.x86_64-w64-mingw32.tar.gz", "3df8d6c511361ed6ad20812f55dca5ad58e4efaee24f34b232492e4e87f6742d"),
        ),
    v"10.2" =>
        Dict(
            MacOS(:x86_64) => ("$bin_prefix/CUDA.v10.2.89-0.1.4.x86_64-apple-darwin14.tar.gz", "5279641e16bec0877e2df7d7986693a02831887b1b47fbb518c1a690793d23d7"),
            Linux(:x86_64, libc=:glibc) => ("$bin_prefix/CUDA.v10.2.89-0.1.4.x86_64-linux-gnu.tar.gz", "6b5e86188278c6de4121f5426b0301aad225e349899f5bd8e7bd119928464dfe"),
            Windows(:x86_64) => ("$bin_prefix/CUDA.v10.2.89-0.1.4.x86_64-w64-mingw32.tar.gz", "0bbd9d0e1ee9a7b4a9268b0cefaf14eb109d72734ec20ae27c16c3d4e07529db"),
        ),
)

# stuff we need to resolve
const products = [
    ExecutableProduct(prefix, "nvdisasm", :nvdisasm),
    ExecutableProduct(prefix, "ptxas", :ptxas),
    FileProduct(prefix, "share/libdevice/libdevice.10.bc", :libdevice),
    FileProduct(prefix, Sys.iswindows() ? "lib/cudadevrt.lib" : "lib/libcudadevrt.a", :libcudadevrt)
]
unsatisfied() = any(!satisfied(p; verbose=verbose) for p in products)

const depsfile = joinpath(@__DIR__, "deps.jl")

function main()
    rm(depsfile; force=true)

    use_binarybuilder = parse(Bool, get(ENV, "JULIA_CUDA_USE_BINARYBUILDER", "true"))
    if use_binarybuilder
        if try_binarybuilder()
            @assert !unsatisfied()
            return
        end
    end

    do_fallback()

    return
end

verlist(vers) = join(map(ver->"$(ver.major).$(ver.minor)", sort(collect(vers))), ", ", " and ")

# download CUDA using BinaryBuilder
function try_binarybuilder()
    @info "Trying to provide CUDA using BinaryBuilder"

    # CUDA version selection
    cuda_version = if haskey(ENV, "JULIA_CUDA_VERSION")
        @warn "Overriding CUDA version to $(ENV["JULIA_CUDA_VERSION"])"
        VersionNumber(ENV["JULIA_CUDA_VERSION"])
    elseif CUDAdrv.functional()
        driver_capability = CUDAdrv.version()
        @info "Detected CUDA driver compatibility $(driver_capability)"

        # CUDA drivers are backwards compatible
        supported_versions = filter(ver->ver <= driver_capability, keys(resources))
        if isempty(supported_versions)
            @warn("""Unsupported version of CUDA; only $(verlist(keys(resources))) are available through BinaryBuilder.
                     If your GPU and driver supports it, you can force a different version with the JULIA_CUDA_VERSION environment variable.""")
            return false
        end

        # pick the most recent version
        maximum(supported_versions)
    else
        @warn("""Could not query CUDA driver compatibility. Please fix your CUDA driver (make sure CUDAdrv.jl works).
                 Alternatively, you can force a CUDA version with the JULIA_CUDA_VERSION environment variable.""")
        return false
    end
    @info "Selected CUDA $cuda_version"

    if !haskey(resources, cuda_version)
        @warn("Requested CUDA version is not available through BinaryBuilder.")
        return false
    end
    download_info = resources[cuda_version]

    # Install unsatisfied or updated dependencies:
    dl_info = choose_download(download_info, platform_key_abi())
    if dl_info === nothing && unsatisfied()
        # If we don't have a compatible .tar.gz to download, complain.
        # Alternatively, you could attempt to install from a separate provider,
        # build from source or something even more ambitious here.
        @warn("Your platform (\"$(Sys.MACHINE)\", parsed as \"$(triplet(platform_key_abi()))\") is not supported through BinaryBuilder.")
        return false
    end

    # If we have a download, and we are unsatisfied (or the version we're
    # trying to install is not itself installed) then load it up!
    if unsatisfied() || !isinstalled(dl_info...; prefix=prefix)
        # Download and install binaries
        install(dl_info...; prefix=prefix, force=true, verbose=verbose)
    end

    # Write out a deps.jl file that will contain mappings for our products
    write_deps_file(depsfile, products, verbose=verbose)

    open(depsfile, "a") do io
        println(io)
        println(io, "const use_binarybuilder = true")
        println(io, "const toolkit_version = $(repr(cuda_version))")
    end

    return true
end

# assume that everything will be fine at run time
function do_fallback()
    @warn "Could not download CUDA dependencies; assuming they will be available at run time"

    open(depsfile, "w") do io
        println(io, "const use_binarybuilder = false")
        for p in products
            if p isa ExecutableProduct
                # executables are expected to be available on PATH
                println(io, "const $(variable_name(p)) = $(repr(basename(p.path)))")
            elseif p isa FileProduct
                # files are more tricky and need to be resolved at run time
                println(io, "const $(variable_name(p)) = Ref{Union{Nothing,String}}(nothing)")
            end
        end
        println(io, "const toolkit_version = Ref{Union{Nothing,VersionNumber}}(nothing)")
        println(io, """
            function check_deps()
                run(pipeline(`ptxas --version`, stdout=devnull))
                run(pipeline(`nvdisasm --version`, stdout=devnull))

                @assert libdevice[] !== nothing
                @assert libcudadevrt[] !== nothing
            end""")
    end

    return
end

main()
