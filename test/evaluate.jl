include("../ide/evaluate.jl")

using Test

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
        module TestModule
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
        module TestModule
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
        module TestModule
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

LiveEval.liveEval(quote module M x = 6 end end)

# ------------ Tests -----------

# This is needed because the `@test` somehow messes with the line numbers.
function testLiveEval(curline::Int, outs::Array, expected::Array)
    expected = [(curline + l-1) => o for (l,o) in expected]
    @test sort(collect(Set(outs)), by=(p)->p[1]) == sort(collect(Set(expected)), by=(p)->p[1])
end

@testset "simple" begin
    testLiveEval(@__LINE__, LiveEval.liveEval(quote x=5 end), [(1 => 5)])

    testLiveEval(@__LINE__, LiveEval.liveEval(quote
             f() = 2
             f()
             function f1(x) x+1 end
             f1(5)
        end), [(2=>2), (3=>2),
               (4=>"f1"), (4=>6), (5=>6), (4=>"f1(5)")])
end
@testset "UserModule" begin
    usermodule = Module(:UserModule)

    testLiveEval(@__LINE__, LiveEval.liveEval(quote
            module M x = 6 end
        end, usermodule), [(2=>usermodule.M), (2 => 6)])

    testLiveEval(@__LINE__, LiveEval.liveEval(quote
             struct X end
             X()
        end, usermodule), [(2=>"X"), (3=>usermodule.X())])
end

@testset "loop" begin
    testLiveEval(@__LINE__, LiveEval.liveEval(quote
            function f()
                x = 0
                while x < 2
                    x+=1
                end
            end
            f()
        end), [(2=>"f"), (2=>"f()"), (3=>0),
                   (4=>true), (4=>true), (4=>false),
                       (5=>1), (5=>2),
               (8=>nothing)])


    testLiveEval(@__LINE__, LiveEval.liveEval(quote
            function f()
                for x in 1:2
                    x
                end
            end
            f()
        end), [(2=>"f"), (2=>"f()"),
                   (3=>1), (3=>2),
                       (4=>1), (4=>2),
               (7=>nothing)])
end


@testset "where T" begin
    testLiveEval(@__LINE__, LiveEval.liveEval(quote
             function f1(x::T) where T
                 x+1
             end
        end), [(2=>"f1")])
end

@testset "Functors" begin
    LiveEval.thunkwrap(quote
            struct X end
            function (x::X)(n)
                n
            end
        end)
end

@testset "break/continue" begin
    LiveEval.thunkwrap(quote
        for x in 1:5
            x > 2 && break
        end
    end)
end

@testset "optional args" begin
    LiveEval.thunkwrap(quote
        function f_optional(a::Int, b = 5)
            (a, b)
        end
    end)
    # calling it
    LiveEval.thunkwrap(quote
        function f_optional(a::Int, b=5)
            (a, b)
        end
        f_optional(5, "HI")
    end)
end
@testset "kwargs" begin
    LiveEval.thunkwrap(quote
        function f_kw(a::Int, b=5; k=2, k1=3)
            (a, b)
        end
        f_kw(2)
    end)
end

@testset "undefined" begin
    testLiveEval(@__LINE__, LiveEval.liveEval(quote
             function f()
                 __undefined__
             end
             Live.@test f()
        end), [(2=>"f"), (2=>"f()"), (5=>nothing), (5=>UndefVarError(:__undefined__))])
end
