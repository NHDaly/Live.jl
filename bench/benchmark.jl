include("../ide/evaluate.jl")

using BenchmarkTools, Statistics
using Test

μs(ns) = ns/1.0e3
ms(ns) = ns/1.0e6
seconds(ns) = ns/1.0e9

# NOTE: tests are strict lower & upper bounds so that I can see the improvement over time.

# Simple example
b = @benchmark LiveEval.liveEval(quote
    2
    3
end, Module())

@testset begin
    @test 0.275 < ms(median(b).time) < 0.375
    @test 1 < ms(maximum(b).time) < 10
end

b = @benchmark LiveEval.liveEval(quote
        module TestModule
        module M
            struct X end
            G = 20
            G + 5
            module Inner
                #println("HI")
                x = 10
            end
            function f(x) x end
            f(2)
            #println(f)
            #println(typeof(f).name.module)
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
end, Module())

@testset begin
    @test 76 < ms(median(b).time) < 80
    @test 80 < ms(maximum(b).time) < 120
end
