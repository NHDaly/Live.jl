using Live

Live.@testfile("$(homedir())/Documents/Live/examples/testedfile_test.jl")

function foo(a,b)
   return (true,false)
end

function foo1(a,b)
	if a < b
    	a + b
    else
        a - b
    end
end
