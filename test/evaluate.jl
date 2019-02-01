import .LiveIDE.LiveEval
import .LiveEval.Cassette

@time e = LiveEval.thunkwrap(quote
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
@time @eval begin
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
 end

@time eval(LiveEval.thunkwrap(quote
    function foo(x)
        if (x > 0)
            102
        elseif (x == 0)
            x+5;
        elseif (x < 10)
            -x;
        else 0 end
    end
    foo(3)
end))
LiveEval.ctx.outputs


LiveEval.thunkwrap(quote
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

# --------- Toplevel tests ----------
# A single module
@eval LiveEval ctx = CollectedOutputs([], [])
@time for toplevel_expr in LiveEval.thunkwrap.((quote
        module Test
            struct X end
            @show X()
            f() = 5
            f()
        end
    end).args)
    eval(toplevel_expr)
end
LiveEval.ctx.outputs

# Embedded Modules
@eval LiveEval ctx = CollectedOutputs([], [])
@time for toplevel_expr in LiveEval.thunkwrap.((quote
        module Test
            struct X end
            @show X()
            f() = 5
            f()
            module Inner
                struct X end
                @show X()
                f() = 5
                f()
            end
        end
    end).args)
    eval(toplevel_expr)
end
LiveEval.ctx.outputs

@time for toplevel_expr in LiveEval.thunkwrap(quote
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
        struct X end
        X()
    end
    end).args
    eval(toplevel_expr)
end
@show LiveEval.ctx.outputs
foo

dump(quote f() = 5 end)

Core.eval(Main, quote Core.eval(Main, (()->quote f2(x) = x+1 end)()) end)

liveEval(quote module M x = 6 end end)
