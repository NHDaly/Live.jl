using Live

Live.@testfile("$(homedir())/Documents/Live/examples/testedfile_test.jl")

function foo1(a,b)
   println("HI")
   return (true,false)
end
