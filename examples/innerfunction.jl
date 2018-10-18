using Live


struct X x end
  


@Live.test x=X(3)
function myScript(x)
  3
  
  @Live.test y=1
  function foo(y)
    y
        
  end
  
  4
  
  return foo(x)
  
  
end


3

  
3

