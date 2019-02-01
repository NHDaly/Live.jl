using Live

# TODO: This still doesn't print callsig like it should
foo() = 2

foo()

# TODO: haha why do these print a weird ([1,2,8])??
function g() end
g()

# simple one-line function
function f(x) x end
Live.@test f(2)

# Call w/ multiple args
Live.@test f1(5,6)
function f1(a, b)
    a + b
end

# Typed args
Live.@test f2(5, "HI")
function f2(a::Int, b::T) where T
    (a, T)
end

# TODO: For some reason this one promotes when printing??
Live.@test f2(2, 3.0)



# Optional args
Live.@test f_optional(5, "HI")
Live.@test f_optional(5)
function f_optional(a::Int, b = 5)
    (a, b)
end


# Keyword args
Live.@test f_key(1)
Live.@test f_key(5, b=2)
function f_key(a::Int; b = 5)
    (a, b)
end

