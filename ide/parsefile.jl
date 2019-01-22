# Copyright © 2018 Nathan Daly

using Live  # For Live-editing this file with LiveIDE.

# Test with this string (Bootstrapped testing! Using parseall to test parseall! XD)
Live.@testfile("../test/parsefile.jl")
function parseall(str)
    return Meta.parse("begin $str end")
end
