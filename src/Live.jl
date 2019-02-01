# Copyright © 2018 Nathan Daly

# This file defines the Live module, which provides macros to test your code
# with the LiveIDE editor.
# These macros will have no effect if executed outside the LiveIDE editor.
module Live

"""
    Live.@test

This is the main interface for Live: Live.@test
Use it to test a function in the LiveIDE. Can be written anywhere.

```julia
using Live

function foo(a,b)
    # ...
end
Live.@test foo(5, zeros(3))
```
"""
macro test(fcall)
    testcall(fcall, __source__.file, __source__.line)
end
# Do nothing by default
function testcall(fcall, file, line) end

"""
    Live.@testfile(testfile)

Test a function via tests defined in a given testfile.

Tests a function with live output in LiveIDE, using whatever parameters are
provided to the function call as called from the corresponding tests in
`testfile`. That file must contain a @test or @testset annotated with the
corresponding `Live.@tested(functionname)`.

See also Live.@tested.

```julia
# src/foo.jl

Live.@testfile("../tests/foo.jl")
function foo(a,b)
    # ...
end

# ----
# tests/foo.jl

Live.@tested(foo)
@testset "foo val" begin
 x = 1
 out = foo(x, x+1)
 @test out.val == true
end
```
"""
macro testfile(files...)
    testfile_call(files, __source__.file, __source__.line)
end
function testfile_call(files, file, line) end


"""
    Live.@script(enable=true)

Enable script-mode in the LiveIDE, causing it to display live output for each
subsequent line of this file. Calling `Live.script(false)` will disable output.
"""
macro script(enable=true)
    script_call(enable, __source__.file, __source__.line)
end
function script_call(enable, file, line) end

end
