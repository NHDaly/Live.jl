import Live
Live.@script()

function helloNathan()
   s = "Hello, World"
   nameindex = match(r"World", s).offset
   s[1:nameindex-1]*"Nathan"
end

Live.@test helloNathan()

function notTested(x)
  return x + 1
end

NOT_DEFINED


if true == true
  5
else
  6
end

Live.@test foo()
function foo()
  if true == false
    5
  else
    6
  end
      
  x = 3
  return x
end


