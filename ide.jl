using Blink

include("parsefile.jl")

cd(@__DIR__)
w = Window(Blink.@d(:async=>false))
#tools(w)

# Set up to allow loading modules
js(w, Blink.JSString("""
    window.nodeRequire = require;
    delete window.require;
    delete window.exports;
    delete window.module;
 """))

load!(w, "frameworks/jquery-3.3.1.js")

# Load codemirror
load!(w, "frameworks/codemirror-5.40.0/lib/codemirror.js")
load!(w, "frameworks/codemirror-5.40.0/lib/codemirror.css")
# Set up for julia:
load!(w, "frameworks/codemirror-5.40.0/mode/julia/julia.js")


html() = """
  <table width="100%">
   <tbody>
    <tr>
     <td>
       <textarea id="text-editor">function myScript()\n   return 100\nend\n</textarea>
     </td>
     <td>
       <textarea id="output-area">output</textarea>
     </td>
    </tr>
   </tbody>
  </table>

  <style>
    table {
        border-collapse: collapse;
    }
    td, th {
        border: 1px solid gray;
        padding: 3px;
    }
  </style>
 """

# Start the editor:
body!(w, html(), async=false)
js(w, Blink.JSString(raw"""
    texteditor = CodeMirror.fromTextArea($("#text-editor")[0], {
        lineNumbers: true,
        mode:  "julia"
    });
    undefined;  // Don't return the CodeMirror object
 """))
js(w, Blink.JSString(raw"""
    outputarea = CodeMirror.fromTextArea($("#output-area")[0], {
        readOnly: true,
        mode:  "julia"
    });
    undefined;  // Don't return the CodeMirror object
 """))

global outputText = @js w outputarea.getValue()

@js w texteditor.on("update",
    (cm) -> (Blink.msg("editorchange", cm.getValue());
             console.log("sent msg to julia!");))

# User code parsing + eval
module UserCode end

numlines(str) = 1+count(c->c=='\n', str)

text = ""
function editorchange(editortext)
    try  # So errors don't crash my Blink window...
        global text, parsed
        text = editortext
        parsed = parseall(editortext)
        lastline = 1
        setOutputText(1, '\n'^numlines(text))
        for node in parsed.args
            isa(node, LineNumberNode) && (lastline = node.line)
            try
                Core.eval(UserCode, node)
            catch e
                setOutputText(lastline, string(e))
            end
        end
    catch err
        println("ERROR: $err")
    end
    nothing
end

function setOutputText(line, text)
    global outputText
    outputLines = split(outputText, '\n')
    textLines = split(text, '\n')
    while length(outputLines) <= line + length(textLines)
        push!(outputLines, "")
    end
    start, finish = line, line+numlines(text)-1
    outputLines[start:finish] = textLines
    # Must use @js_ since no return value required. (@js hangs)
    #@js_ w outputarea.replaceRange($text, CodeMirror.Pos($start, 0), CodeMirror.Pos($finish, 0))
    outputText = join(outputLines, "\n")
    @js_ w outputarea.setValue($outputText)
end

Blink.handlers(w)["editorchange"] = editorchange
