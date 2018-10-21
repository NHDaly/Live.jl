import Live
Live.@script()

Live.@test 
function helloNathan()
   s = "Hello, World"
   nameindex = match(r"World", s).offset
   s[1:nameindex-1]*"Nathan"
end

helloNathan()


function notTested(x)
  return x + 1
end
notTested(10)

NOT_DEFINED


if true == true
  5
else
  6
end


Live.@test 
function foo()
  if true == false
    5
  else
    6
  end
      
  x = 3
  return x
end
    

