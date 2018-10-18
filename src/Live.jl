# This file defines the Live module, which provides macros to test your code
# with the LiveIDE editor.
# These macros will have no effect if executed outside the LiveIDE editor.
module Live
  struct TestLine
      args
      lineNode::LineNumberNode
  end

  macro test(args...)
      TestLine(args, __source__)
  end
end
