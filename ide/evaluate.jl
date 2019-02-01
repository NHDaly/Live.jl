# Copyright © 2018 Nathan Daly

module LiveEval

mutable struct CollectedOutputs
    outputs
    linestack::Vector{Int}
end
ctx = CollectedOutputs([], [1])  # Initialize to start with line 1

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
# Final leaf nodes
function thunkwrap(head, expr::Expr)
    return :( $record_thunk(()->$expr) )
end
# Special cases
function thunkwrap(head::Val{:function}, expr::Expr)
    if length(expr.args) >= 2
        expr.args[2] = thunkwrap(expr.args[2])
    end
    fname = expr.args[1].args[1]

    startline_var = gensym("$(fname)_startline")
    # Add printing the function call w/ args to the body
    if length(expr.args) >= 2
        argvals = expr.args[1].args[2:end]
        calc_callval_expr = :($(String(fname))*"($(join([$(argvals...)], ',')))")
        # Print it onto the first line of the function definition, assigned to a global below.
        pushfirst!(expr.args[2].args, :(
            push!($ctx.outputs, ($startline_var => $calc_callval_expr));
        ))
    end

    # Record the function definition starting line to later print the function call
    return :(const $startline_var = $ctx.linestack[end];
             $expr; $(thunkwrap(String(fname))) )
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

# Loops
function thunkwrap(head::Val{:while}, expr::Expr)
    # Thunkwrap all exprs
    for (i,node) in enumerate(expr.args)
        expr.args[i] = thunkwrap(node)
    end

    # Push the last line on again, so it lasts throughout the loop
    startline_var = gensym(:startline)
    preloop = :($startline_var = $LiveEval.ctx.linestack[end])
    pushline = :(push!($LiveEval.ctx.linestack, $startline_var))
    #expr.args[1] = :( $pushline; $(expr.args[1]) )

    #loop_outputs = CollectedOutputs[]
    ##output_channels = Channel{CollectedOutputs}[]
    #outputs_var = gensym(:outputs)
    #startloop = :($outputs_var = $CollectedOutputs([], [1]))
    #endloop   = :($((o)->push!(loop_outputs, o))($outputs_var))
    ##expr.args[2].args = [startloop, expr.args[2].args..., endloop]
    #expr.args[2].args = [pushline, expr.args[2].args...]

    expr.args[2].args = [expr.args[2].args..., pushline]
    return :($preloop; $expr)
end
function thunkwrap(head::Val{:for}, expr::Expr)
    # Thunkwrap body
    expr.args[2] = thunkwrap(expr.args[2])

    # Thunkwrap the iteration variable (need to do this manually, unlike while-loop)
    println = thunkwrap(expr.args[1].args[1])

    # Push the last line on again, so it lasts throughout the loop
    startline_var = gensym(:startline)
    preloop = :($startline_var = $LiveEval.ctx.linestack[end])
    # This is harder cause the for loop runs exactly the right amount of times, so i only
    # want to push n-1 times
    pushline = :(push!($LiveEval.ctx.linestack, $startline_var))
    popline = :(pop!($LiveEval.ctx.linestack))

    expr.args[2].args = [pushline, println, expr.args[2].args...]
    return :($preloop; $popline; $expr)
end


function record_thunk(linenode::LineNumberNode)
    push!(ctx.linestack, linenode.line)
end
thunkwrap(linenode::LineNumberNode) =
                :( $record_thunk(LineNumberNode($(linenode.line), $(string(linenode.file)))) )
thunkwrap(literal) = :( $record_thunk(()->$literal) )



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
thunkwrap(head::Val{:include}, expr::Expr) = expr
struct LiveIDEFile
    filename::String
end
function thunkwrap(head::Val{:macrocall}, expr::Expr)
    if length(expr.args) >= 2
        expr.args[2] = LineNumberNode(expr.args[2].line, LiveIDEFile(":none:"))
    end
    # Complicated return value to wrap without recursion
    val = gensym()
    :( $val = $expr; $(thunkwrap(val)) )
end

# -------- Live functions
using Live

include("live.jl")

#
#function thunkwrap(head::Val{:macrocall}, expr::Expr)
#
#end


# -------- whole file

include("parsefile.jl")

function liveEval(expr, usermodule=@__MODULE__)
    @assert expr.head == :block
    global ctx = CollectedOutputs([], [1]) # Initialize to start on line 1

    Live.reset_testfuncs()

    for toplevel_expr in LiveEval.thunkwrap.(expr.args)
        try
            Core.eval(usermodule, toplevel_expr)
        catch e
            push!(ctx.outputs, (pop!(ctx.linestack) => e))
            #Base.display_error(e)
        end
    end
    run_all_livetests(usermodule)
    return ctx.outputs
end

function run_all_livetests(usermodule)
    for testthunk in Live.testthunks
        @eval usermodule $testthunk()
    end
end
# -----------

end
