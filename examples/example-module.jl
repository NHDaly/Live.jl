
module M

mutable struct X{T<:Number}
  x::T
  y::Int
  
end

X() = X{Int}(1,2)

end