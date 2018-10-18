# This file defines the Live module, which provides macros to test your code
# with the LiveIDE editor.
# These macros will have no effect if executed outside the LiveIDE editor.
module Live

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
end
