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
