# https://stackoverflow.com/a/46366560/751061
# modified from the julia source ./test/parse.jl
function parseall(str)
    pos = start(str)
    exprs = []
    parsed = nothing
    while !done(str, pos)
            linenum = 1+count(c->c=='\n', str)
        if pos < length(str)
            firstnonspace = match(r"\S", str[pos:end])
            if firstnonspace != nothing
                index = pos + firstnonspace.offset - 1
                linenum = 1+count(c->c=='\n', str[1:index])
            end
        end
        push!(exprs, LineNumberNode(linenum, :none))
        ex, pos = parse(str, pos) # returns next starting point as well as expr
        if ex isa Symbol
            push!(exprs, ex)
        elseif ex isa Expr
            ex.head == :toplevel ? exs = ex.args : exs = [ex] #see StackOverflow comments for info
            for ex in exs
                #if ex.head == :using
                #    eval(ex)  # eval :using Expressions globally rather than inserting.
                #else
                push!(exprs, ex)
                #end
            end
        end
    end
    if length(exprs) == 0
        return nothing
    #elseif length(exprs) == 1
    #    return exprs[1]
    else
        return Expr(:block, exprs...) # convert the array of expressions
                                      # back to a single expression
    end
end
