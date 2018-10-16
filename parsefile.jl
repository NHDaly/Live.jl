# https://stackoverflow.com/a/46366560/751061
# modified from the julia source ./test/parse.jl
function parseall(str)
    pos = firstindex(str)
    exprs = []
    parsed = nothing
    while pos <= ncodeunits(str)
        linenum = 1
        nextstart = pos
        if pos < ncodeunits(str)
            firstnonspace = match(r"\S", str[pos:end])
            if firstnonspace != nothing
                nextstart = pos + firstnonspace.offset - 1
                linenum = 1+count(c->c=='\n', str[1:nextstart])
            end
        end
        push!(exprs, LineNumberNode(linenum, :none))
        ex, pos = Meta.parse(str, nextstart) # returns next starting point as well as expr
        if ex isa Expr
            ex.head == :toplevel ? exs = ex.args : exs = [ex] #see StackOverflow comments for info
            for e in exs
                #if e.head == :using
                #    eval(e)  # eval :using Expressions globally rather than inserting.
                #else
                push!(exprs, e)
                #end
            end
        else  # Symbol/Literal
            push!(exprs, ex)
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
