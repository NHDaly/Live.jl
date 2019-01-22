# Copyright © 2018 Nathan Daly

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
   fname = expr.args[1].args[1]
    return quote ($expr; $(thunkwrap(String(fname)))) end
    # return expr
    #return quote Thunk(()->$expr)() end
end
function thunkwrap(head::Val{:(=)}, expr::Expr)
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
function Cassette.execute(ctx::LiveCtx, line::LineNodeThunk)
    ctx.metadata.lastline = line.linenode.line
    nothing
end

_ctx = LiveCtx(metadata = CollectedOutputs([], 0))
@time @eval Cassette.overdub($_ctx, ()->$(thunkwrap(quote
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
_ctx.metadata.outputs

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
    quote Core.eval(@__MODULE__, $(thunkwrap(head,expr))) end
    #return quote Thunk(()->$(thunkwrap(head,expr)))() end
end
## Valid top-level expressions:
thunkwrap_toplevel(head::Val{:struct}, expr::Expr) = thunkwrap(quote Core.eval(@__MODULE__, $(QuoteNode(expr))) end)
thunkwrap_toplevel(head::Val{:import}, expr::Expr) = thunkwrap(quote Core.eval(@__MODULE__, $(QuoteNode(expr))) end)
thunkwrap_toplevel(head::Val{:using}, expr::Expr) = thunkwrap(quote Core.eval(@__MODULE__, $(QuoteNode(expr))) end)
thunkwrap_toplevel(head::Val{:(=)}, expr::Expr) = thunkwrap(quote Core.eval(@__MODULE__, $(QuoteNode(expr))) end)
function thunkwrap_toplevel(head::Val{:function}, expr::Expr)
    thunkwrap(quote Core.eval(@__MODULE__, $(QuoteNode(thunkwrap(expr)))) end)
end


struct ModuleThunk
    expr
    parent
end
(thunk::ModuleThunk)() = Core.eval(thunk.parent, thunk.expr)

function thunkwrap_toplevel(head::Val{:module}, expr::Expr)
    expr.args[3] = thunkwrap_toplevel(expr.args[3])
    return quote ModuleThunk($(QuoteNode(expr)), @__MODULE__)() end
end

function Cassette.execute(ctx::LiveCtx, f::ModuleThunk)::Module
    #push!(ctx.metadata.outputs, (ctx.metadata.lastline => output))
    f.expr.args[3] = quote
        LineNodeThunk = $(@__MODULE__).LineNodeThunk
        Thunk = $(@__MODULE__).Thunk
        ModuleThunk = $(@__MODULE__).ModuleThunk
        #$(thunkwrap_toplevel(expr.args[3]))
        Cassette = $(@__MODULE__).Cassette
        Cassette.overdub($ctx, ()->$(f.expr.args[3]))
    end
    #println(expr)
    #thunkwrap(quote eval($(QuoteNode(expr))) end)
    Core.eval(f.parent, f.expr)::Module
end

_ctx = LiveCtx(metadata = CollectedOutputs([], 0))
@time @eval Cassette.overdub($_ctx, ()->$(thunkwrap_toplevel(quote
    module Test
    module M
        struct X end
        G = 20
        G + 5
        module Inner
            println("HI")
            x = 10
        end
        function f(x) x end
        f(2)
        println(f)
        println(typeof(f).name.module)
    end
    M.G + 100
    M.Inner.x
    function foo(x)
        y = x
        if (y > 0)
            function helper(y)
              y+100
            end
            helper(10)
        elseif (x == 0)
            x+5;
        elseif (x < 10)
            -x;
        else 0 end
    end
    foo(3)
    M.f("hey")
end
end)))
@show _ctx.metadata.outputs
foo

dump(quote f() = 5 end)

Core.eval(Main, quote Core.eval(Main, (()->quote f2(x) = x+1 end)()) end)

# -------- whole file

include("parsefile.jl")

function liveEvalCassette(expr)
    ctx = LiveCtx(metadata = CollectedOutputs([], 0))
    @eval Cassette.overdub($ctx, ()->$(thunkwrap_toplevel(expr)))
    return ctx.metadata.outputs
end

_ctx = LiveCtx(metadata = CollectedOutputs([], 0))
@time @eval Cassette.overdub($_ctx, ()->$(thunkwrap_toplevel(
    parseall(read("$(@__DIR__)/../examples/example2.jl", String), filename=@__FILE__))))
@show _ctx.metadata.outputs

@show liveEvalCassette(parseall(read("$(@__DIR__)/../examples/example2.jl", String), filename=@__FILE__))


# -----------

end
