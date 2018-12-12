module CassetteLive

using Cassette

struct Thunk{F<:Function}
    f::F
end
(thunk::Thunk)() = thunk.f()

thunkwrap(expr::Expr) = thunkwrap(Val(expr.head), expr)
function thunkwrap(head::Val{:block}, expr::Expr)
    for (i,node) in enumerate(expr.args)
        expr.args[i] = thunkwrap(node)
    end
    return expr
end
function thunkwrap(head::Val{:function}, expr::Expr)
    expr.args[2] = thunkwrap(expr.args[2])
    return expr
    #return quote Thunk(()->$expr)() end
end
function thunkwrap(head::Union{Val{:if},Val{:elseif}}, expr::Expr)
    for (i,node) in enumerate(expr.args)
        expr.args[i] = thunkwrap(node)
    end
    return expr
end
# Final leaf nodes
function thunkwrap(head, expr::Expr)
    return quote Thunk(()->$expr)() end
end

struct LineNodeThunk
    linenode::LineNumberNode
end
(thunk::LineNodeThunk)() = nothing
thunkwrap(linenode::LineNumberNode) =
                quote LineNodeThunk(LineNumberNode($(linenode.line), $(string(linenode.file))))() end
thunkwrap(literal) = quote Thunk(()->$literal)() end

@time e = thunkwrap(quote
    function foo(x)
        if (x > 0)
            100
        elseif (x == 0)
            x+5;
        elseif (x < 10)
            -x;
        else 0 end
     end
     foo(3)
end)
@time eval(e)


# Now that that's all set up, we can use cassette to capture the values from those thunks!

Cassette.@context LiveCtx

mutable struct CollectedOutputs
    outputs
    lastline::Int
end
function Cassette.posthook(ctx::LiveCtx, output, f::Thunk)
    push!(ctx.metadata.outputs, (ctx.metadata.lastline => output))
end
function Cassette.execute(::LiveCtx, line::LineNodeThunk)
    ctx.metadata.lastline = line.linenode.line
    nothing
end

ctx = LiveCtx(metadata = CollectedOutputs([], 0))
@time @eval Cassette.overdub(ctx, ()->$(thunkwrap(quote
    function foo(x)
        if (x > 0)
            100
        elseif (x == 0)
            x+5;
        elseif (x < 10)
            -x;
        else 0 end
    end
    foo(3)
end)))

ctx.metadata.outputs

# ------- top level statements

thunkwrap_toplevel(expr::Expr) = thunkwrap_toplevel(Val(expr.head), expr)
function thunkwrap_toplevel(head::Val{:block}, expr::Expr)
    for (i,node) in enumerate(expr.args)
        expr.args[i] = thunkwrap_toplevel(node)
    end
    return expr
end
thunkwrap_toplevel(linenode::LineNumberNode) = thunkwrap(linenode)
thunkwrap_toplevel(literal) = thunkwrap(literal)
# Final leaf nodes just fall-back to thunkwrap:
function thunkwrap_toplevel(head, expr::Expr)
    thunkwrap(head,expr)
    #return quote Thunk(()->$(thunkwrap(head,expr)))() end
end
## Valid top-level expressions:
thunkwrap_toplevel(head::Val{:struct}, expr::Expr) = thunkwrap(quote eval($(QuoteNode(expr))) end)
thunkwrap_toplevel(head::Val{:import}, expr::Expr) = thunkwrap(quote eval($(QuoteNode(expr))) end)
thunkwrap_toplevel(head::Val{:using}, expr::Expr) = thunkwrap(quote eval($(QuoteNode(expr))) end)
thunkwrap_toplevel(head::Val{:(=)}, expr::Expr) = thunkwrap(quote eval($(QuoteNode(expr))) end)

struct ModuleThunk
    expr
end
(thunk::ModuleThunk)() = eval(thunk.expr)

function thunkwrap_toplevel(head::Val{:module}, expr::Expr)
    return quote ModuleThunk($(QuoteNode(expr)))() end
end

function Cassette.execute(ctx::LiveCtx, f::ModuleThunk)::Module
    #push!(ctx.metadata.outputs, (ctx.metadata.lastline => output))
    f.expr.args[3] = quote
        LineNodeThunk = $(@__MODULE__).LineNodeThunk
        Thunk = $(@__MODULE__).Thunk
        ModuleThunk = $(@__MODULE__).ModuleThunk
        #$(thunkwrap_toplevel(expr.args[3]))
        Cassette = $(@__MODULE__).Cassette
        Cassette.overdub($ctx, ()->$(thunkwrap_toplevel(f.expr.args[3])))
    end
    #println(expr)
    #thunkwrap(quote eval($(QuoteNode(expr))) end)
    eval(f.expr)::Module
end

ctx = LiveCtx(metadata = CollectedOutputs([], 0))
@time @eval Cassette.overdub(ctx, ()->$(thunkwrap_toplevel(quote
    module M
        struct X end
        G = 20
        G + 5
        println("HI")
    end
    function foo(x)
        if (x > 0)
            100
        elseif (x == 0)
            x+5;
        elseif (x < 10)
            -x;
        else 0 end
    end
    foo(3)
end)))
@show ctx.metadata.outputs

# -------- whole file

include("parsefile.jl")
ctx = LiveCtx(metadata = CollectedOutputs([], 0))
@time @eval Cassette.overdub(ctx,
    ()->$(thunkwrap_toplevel(parseall(read("$(@__DIR__)/../examples/modules.jl", String)))))
@show ctx.metadata.outputs


# -----------

end
