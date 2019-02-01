using Test
#include("$(homedir())/Documents/Live/examples/testedfile.jl")

@testset "foo" begin
  Test.@test foo() == (true,false)
end

@testset "foo1" begin
  Test.@test foo1(2, 3) == 5
  Test.@test foo1(3, 3) == 0
end
