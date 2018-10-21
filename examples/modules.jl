import Live
Live.@script()

module M

module Inner

x = 3

x
end

function myScript()
   return 100
end


end


M.Inner.x

M.myScript()