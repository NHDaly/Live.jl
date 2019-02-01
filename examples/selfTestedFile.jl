using Live
Live.@testfile("$(homedir())/Documents/Live/examples/testedfile_test.jl")

function foo(a,b)
   return (true,false)
end
