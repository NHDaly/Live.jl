using Live
Live.@script()

struct X x end

@Live.test x=X(3)
function testx(x)

  @Live.test y=1
  function foo(y)
    y
  end

  return foo(x)
end

3
3
