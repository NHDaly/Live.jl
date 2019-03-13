module Runtests
using Pkg
Pkg.activate("$(@__DIR__)/../ide")

using Test

@testset "evaluate" begin
    include("evaluate.jl")
end
@testset "parsefile" begin
    include("parsefile.jl")
end
end
