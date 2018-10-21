using Live
Live.@script()

using Test

include("../ide/parsefile.jl")


@test length(parseall("a").args) == 2

@test :x in parseall("x").args
@test :y in parseall("x; y").args

@testset "..." begin
	@test :y in parseall("x; y").args
end