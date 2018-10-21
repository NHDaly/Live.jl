using Live
Live.@script()

using Test

foo() = 5

@test 5 == 5

@testset "passing" begin
	@test foo() == 5
end
@testset "failing" begin
	@test foo() == 6
end
