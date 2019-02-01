using Test
#include("$(homedir())/Documents/Live/examples/selfTestedFile.jl")

println("HI! Module: $(@__MODULE__)")

@testset "foo" begin
  Test.@test foo(2,3) == (true,false)
end

@testset "foo" begin
  Test.@test foo1(2,3) == (true,false)
  Test.@test foo1(3,3) == (true,false)
end
