using Live
Live.@script()

module Test

# Loops
function f(x)
 	out = 0
	for x in 1:4
        if x == 2
            continue
        end
    	z = 2*x
        out += z
	end
    out
end
f(5)


function f(x)
 	out = 0
	while x > 0
    	out += x
        x -= 1
	end
    out
end
f(5)


end
