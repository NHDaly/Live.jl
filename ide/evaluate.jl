# Copyright © 2018 Nathan Daly

module LiveEval

mutable struct CollectedOutputs
    outputs
    linestack::Vector{Int}
end
ctx = CollectedOutputs([], [])

function record_thunk(f::Function)
    global ctx
    val = f()
    push!(ctx.outputs, (pop!(ctx.linestack) => val))
    val
end

thunkwrap(expr::Expr) = thunkwrap(Val(expr.head), expr)
function thunkwrap(head::Val{:block}, expr::Expr)
    for (i,node) in enumerate(expr.args)
        expr.args[i] = thunkwrap(node)
    end
    return expr
end
function thunkwrap(head::Val{:function}, expr::Expr)
    expr.args[2] = thunkwrap(expr.args[2])
    fname = expr.args[1].args[1]
    return quote ($expr; $(thunkwrap(String(fname)))) end
    # return expr
    #return quote record_thunk(()->$expr) end
end
function thunkwrap(head::Val{:(=)}, expr::Expr)
    # Check for `f(x) = x` style function definition
    if (expr.args[1] isa Expr && expr.args[1].head == :call)
        return thunkwrap(Val(:function), expr)
    end
    expr.args[2] = thunkwrap(expr.args[2])
    return expr
end
function thunkwrap(head::Union{Val{:if},Val{:elseif}}, expr::Expr)
    for (i,node) in enumerate(expr.args)
        expr.args[i] = thunkwrap(node)
    end
    return expr
end
# Final leaf nodes
function thunkwrap(head, expr::Expr)
    return quote $record_thunk(()->$expr) end
end

function record_thunk(linenode::LineNumberNode)
    push!(ctx.linestack, linenode.line)
end
thunkwrap(linenode::LineNumberNode) =
                quote $record_thunk(LineNumberNode($(linenode.line), $(string(linenode.file)))) end
thunkwrap(literal) = quote $record_thunk(()->$literal) end



# ------- top level statements

# Just descend into the module's contents
function thunkwrap(head::Val{:module}, expr::Expr)
    expr.args[3].args = [(thunkwrap.(expr.args[3].args))...]
    # Print the name of the module before defining it
    pushfirst!(expr.args[3].args, thunkwrap(expr.args[2]))
    expr
end
function thunkwrap(head::Val{:struct}, expr::Expr)
    # Print the name of the struct before defining it
    #return expr
    return :($(thunkwrap(string(expr.args[2]))); $expr)
end
# Ignore these toplevel expressions
thunkwrap(head::Val{:import}, expr::Expr) = expr
thunkwrap(head::Val{:using}, expr::Expr) = expr

# -------- whole file

include("parsefile.jl")

function liveEval(expr, usermodule=@__MODULE__)
    @assert expr.head == :block
    global ctx = CollectedOutputs([], [1]) # Initialize to start on line 1
    for toplevel_expr in LiveEval.thunkwrap.(expr.args)
        try
            Core.eval(usermodule, toplevel_expr)
        catch e
            push!(ctx.outputs, (pop!(ctx.linestack) => e))
            #Base.display_error(e)
        end
    end
    return ctx.outputs
end


# -----------

end
