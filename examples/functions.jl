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



# Recursive
# TODO: something screwy with printing, after changes
Live.@test fact(3)
function fact(x)
    x <= 1 && return 1
    return x * fact(x-1)
end

Live.@test fact_explicit(3)
function fact_explicit(x)
    if x <= 1
        out = 1
        return out
    end
    v = fact_explicit(x-1)
    v1 = x*v
    return v
end


