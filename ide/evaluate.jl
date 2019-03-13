# Copyright © 2018 Nathan Daly

module LiveEval

using Rematch
import CodeTools  # For withpath (for evaling in the correct file)

mutable struct CollectedOutputs
    outputs
    linestack::Vector{Int}
end
ctx = CollectedOutputs([], [1])  # Initialize to start with line 1

function record_thunk(val)
    global ctx
    #quote
        #val = $expr
        push!(ctx.outputs, (pop!(ctx.linestack) => val))
        val
    #end
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
    return :($record_thunk($expr))
end
# Special cases
function thunkwrap(head::Val{:function}, expr::Expr)
    callsig = nothing
    try
        @match Expr(_, [callsig, body]) = expr
        while callsig.head == :where
            callsig = callsig.args[1]
        end
    catch
        # If this is an empty function definition, return
        return
    end

    expr.args[2] = thunkwrap(expr.args[2])
    fname = callsig.args[1]

    startline_var = gensym("$(fname)_startline")
    # Add printing the function call w/ args to the body
    if length(expr.args) >= 2
        argvals = argnames(callsig)
        calc_callval_expr = :($(string(fname))*"($(join([$(argvals...)], ',')))")
        # Print it onto the first line of the function definition, assigned to a global below.
        pushfirst!(expr.args[2].args, :(
            push!($ctx.outputs, ($startline_var => $calc_callval_expr));
        ))
    end

    # Record the function definition starting line to later print the function call
    return :($startline_var = $ctx.linestack[end];
             $expr; $(thunkwrap(string(fname))) )
end

argnames(fcall::Expr) = argnames(fcall.args[2:end])
function argnames(args::Array)
    out = []
    kwargs_out = []
    for a in args
        @match a begin
            # Note: Order is significant here.
            Expr(:parameters, kwargs) => (kwargs_out = argnames(kwargs))
            Expr(_, [name, _]) => push!(out, name)
            value => push!(out, value)
        end
    end
    return [out..., kwargs_out...]
end

function thunkwrap(head::Val{:(=)}, expr::Expr)
    if Base.is_short_function_def(expr)
        # Check for `f(x) = x` style function definition
        return thunkwrap(Val(:function), expr)
    else
        expr.args[2] = thunkwrap(expr.args[2])
            return expr
    end
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
# Control flow statements that don't create a value, need to manually pop their linenumber.
thunkwrap(head::Val{:continue}, expr::Expr) = :(pop!($ctx.linestack); $expr)
thunkwrap(head::Val{:break}, expr::Expr) = :(pop!($ctx.linestack); $expr)


function record_linenode(linenode::LineNumberNode)
    push!(ctx.linestack, linenode.line)
end
thunkwrap(linenode::LineNumberNode) =
                :( $record_linenode(LineNumberNode($(linenode.line), $(string(linenode.file)))) )
thunkwrap(literal) = @match literal begin
    Symbol("_") => literal
    _ => :($record_thunk($literal))
end



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
thunkwrap(head::Val{:export}, expr::Expr) = expr
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

function liveEval(expr, usermodule=@__MODULE__, file=nothing)
    @assert expr.head == :block
    global ctx = CollectedOutputs([], [1]) # Initialize to start on line 1

    Live.reset_testfuncs()

    for toplevel_expr in thunkwrap.(expr.args)
        try
            CodeTools.withpath(file) do
                Core.eval(usermodule, toplevel_expr)
            end
        catch e
            if length(ctx.linestack) > 0
                push!(ctx.outputs, (pop!(ctx.linestack) => e))
            else
                # For erorrs that happen before we've executed any code.
                Base.display_error(e, Base.catch_backtrace())
            end
        end
    end
    run_all_livetests(usermodule, file)
    return ctx.outputs
end

function run_all_livetests(usermodule, file)
    for testthunk in Live.testthunks
        CodeTools.withpath(file) do
            @eval usermodule $testthunk()
        end
    end
end
# -----------

end
