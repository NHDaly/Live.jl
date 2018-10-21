using Live
Live.@script()

using Test

# src/foo.jl

Live.@testfile(@__FILE__)
function foo(a,b)
   return (true,false)
end

# ----
# tests/foo.jl

Live.@tested(foo)
Test.@testset "foo val" begin
 x = 1
 out = foo(x, x+1)
 Test.@test out[1] == true
end

