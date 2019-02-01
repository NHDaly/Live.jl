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
    expr.args[2] = thunkwrap(expr.args[2])
    return expr
    #return quote record_thunk(()->$expr) end
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

# thunkwrap_toplevel is like thunkwrap, except it returns _multiple_ toplevel statements
#thunkwrap_toplevel(expr::Expr) = (thunkwrap_toplevel(Val(expr.head), expr))
#wrap_multiple(expr::Expr) = [expr,]
#wrap_multiple(c) = c
#function thunkwrap_toplevel(head::Val{:block}, expr::Expr)
#    for (i,node) in enumerate(expr.args)
#        expr.args[i] = thunkwrap_toplevel(node)
#    end
#    return expr
#end

thunkwrap_toplevel(e) = thunkwrap(e)

# Just descend into the module's contents
function thunkwrap(head::Val{:module}, expr::Expr)
    expr.args[3].args = [(thunkwrap_toplevel.(expr.args[3].args))...]
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
#thunkwrap(head::Val{:(=)}, expr::Expr) = expr
#function thunkwrap_toplevel(head::Val{:function}, expr::Expr)
#    thunkwrap(:( Core.eval(@__MODULE__, $(QuoteNode(thunkwrap(expr)))) ))
#end

#thunkwrap_toplevel(expr::Expr) = thunkwrap_toplevel(Val(expr.head), expr)
#function thunkwrap_toplevel(head::Val{:block}, expr::Expr)
#    for (i,node) in enumerate(expr.args)
#        expr.args[i] = thunkwrap_toplevel(node)
#    end
#    return expr
#end
#thunkwrap_toplevel(linenode::LineNumberNode) = thunkwrap(linenode)
#thunkwrap_toplevel(literal) = thunkwrap(literal)
## Final leaf nodes just fall-back to thunkwrap:
#function thunkwrap_toplevel(head, expr::Expr)
#    quote Core.eval(@__MODULE__, $(thunkwrap(head,expr))) end
#    #return quote record_thunk(()->$(thunkwrap(head,expr)))() end
#end
### Valid top-level expressions:
#thunkwrap_toplevel(head::Val{:struct}, expr::Expr) = thunkwrap(:( Core.eval(@__MODULE__, $(QuoteNode(expr))) ))
#thunkwrap_toplevel(head::Val{:import}, expr::Expr) = thunkwrap(:( Core.eval(@__MODULE__, $(QuoteNode(expr))) ))
#thunkwrap_toplevel(head::Val{:using}, expr::Expr) = thunkwrap(:( Core.eval(@__MODULE__, $(QuoteNode(expr))) ))
#thunkwrap_toplevel(head::Val{:(=)}, expr::Expr) = thunkwrap(:( Core.eval(@__MODULE__, $(QuoteNode(expr))) ))
#function thunkwrap_toplevel(head::Val{:function}, expr::Expr)
#    thunkwrap(:( Core.eval(@__MODULE__, $(QuoteNode(thunkwrap(expr)))) ))
#end


#struct ModuleThunk
#    expr
#    parent
#end
#(thunk::ModuleThunk)() = Core.eval(thunk.parent, thunk.expr)
#
#function thunkwrap_toplevel(head::Val{:module}, expr::Expr)
#    expr.args[3] = thunkwrap_toplevel(expr.args[3])
#    return quote $ModuleThunk($(QuoteNode(expr)), @__MODULE__)() end
#end
#
#function Cassette.execute(ctx::LiveCtx, f::ModuleThunk)::Module
#    #push!(ctx.outputs, (ctx.lastline => output))
#    f.expr.args[3] = quote
#        record_thunk = $(@__MODULE__).record_thunk
#        record_thunk = $(@__MODULE__).record_thunk
#        ModuleThunk = $(@__MODULE__).ModuleThunk
#        #$(thunkwrap_toplevel(expr.args[3]))
#        Cassette = $(@__MODULE__).Cassette
#        Cassette.overdub($ctx, ()->$(f.expr.args[3]))
#    end
#    #println(expr)
#    #thunkwrap(quote eval($(QuoteNode(expr))) end)
#    Core.eval(f.parent, f.expr)::Module
#end

# -------- whole file

include("parsefile.jl")

function liveEval(expr, usermodule=@__MODULE__)
    @assert expr.head == :block
    global ctx = CollectedOutputs([], [])
    #try
        for toplevel_expr in LiveEval.thunkwrap.(expr.args)
            Core.eval(usermodule, toplevel_expr)
        end
    #catch e
    #    Base.display_error(e)
    #end
    return ctx.outputs
end

liveEval(quote module M x = 6 end end)

#function liveEvalCassette(expr, usermodule=@__MODULE__)
#    ctx = LiveCtx(metadata = CollectedOutputs([], []))
#    try
#    @eval usermodule $Cassette.overdub($ctx, ()->$(thunkwrap_toplevel(expr)))
#    catch e
#        Base.display_error(e)
#    end
#    return ctx.outputs
#end

#@show liveEvalCassette(parseall(read("$(@__DIR__)/../examples/example2.jl", String)))


# -----------

end
