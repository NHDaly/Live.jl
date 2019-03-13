using Live

using Test

include("../ide/parsefile.jl")

Test.@testset "..." begin
  expr1 = "x + 1"
  expr2 = "function foo() return 3 end"
  Test.@test :(x+1) in parseall(expr1*"\n"*expr2).args
end

Test.@test length(parseall("a").args) == 2

Test.@test :x in parseall("x").args
Test.@test :y in parseall("x; y").args
