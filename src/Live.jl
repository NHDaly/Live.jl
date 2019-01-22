# Copyright © 2018 Nathan Daly

# This file defines the Live module, which provides macros to test your code
# with the LiveIDE editor.
# These macros will have no effect if executed outside the LiveIDE editor.
module Live

"""
    Live.@script(enable=true)

Enable script-mode in the LiveIDE, causing it to display live output for each
subsequent line of this file. Calling `Live.script(false)` will disable output.
"""
macro script(enable=true)
    ScriptLine(enable)
end
# This struct tells LiveIDE to enable/disable script-mode.
struct ScriptLine
    enabled::Bool
end

"""
    Live.@test

This is the main interface for Live: Live.@test
Use it to test a function in the LiveIDE by annotating the function with this
macro on its own line:

```julia
using Live

Live.@test a=5 b=zeros(3)
function foo(a,b)
    # ...
end
```
"""
macro test(args...)
    TestLine(args, __source__)
end

# This struct is used by the IDE to pass a context (args) into a function when
# executing it via Live.@test
struct TestLine
    args
    lineNode::LineNumberNode
end

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
    TestFileLine(files, __source__)
end

struct TestFileLine
    files
    lineNode::LineNumberNode
end

"""
    Live.@tested(functionname)

Record a @test's or @testset's calls to `functionname` for testing that function
in LiveIDE.

If the provided function (`functionname`) is annotated with a `Live.@testfile`
that includes this test file, then any time that function is invoked from this
@test or @testset, the parameters passed to that function will be available as
inputs for live debug output in the LiveIDE where that function is defined.

See also Live.@testfile.

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
macro tested(functionname)
    TestedLine(functionname)
end

struct TestedLine
    functionname
end

end
