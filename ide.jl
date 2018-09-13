using Blink

include("parsefile.jl")

cd(@__DIR__)
w = Window(Blink.@d(:async=>false))
#tools(w)

# Set up to allow loading modules
js(w, Blink.JSString("""
    window.nodeRequire = require;
    window.nodeExports = window.exports;
    window.nodeModule = window.module;
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
  <table width="100%" height="100%">
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
    html, body, table, .CodeMirror {
        height: 100%;
    }
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
numlines(str) = 1+count(c->c=='\n', str)

function setOutputText(line, text)
    global outputText
    outputLines = split(outputText, '\n')
    #println("before: $outputLines")
    textLines = split(text, '\n')
    while length(outputLines) <= line + length(textLines)
        push!(outputLines, "")
    end
    start, finish = line, line+numlines(text)-1
    outputLines[start:finish] = textLines
    # Must use @js_ since no return value required. (@js hangs)
    #@js_ w outputarea.replaceRange($text, CodeMirror.Pos($start, 0), CodeMirror.Pos($finish, 0))
    #println("after: $outputLines")
    outputText = join(outputLines, "\n")
    outputText = rstrip(outputText)
    @js_ w outputarea.setValue($outputText)
end


# Handle more interactivity for users
module Live
  struct TestLine
      args
      lineNode::LineNumberNode
  end

  macro test(args...)
      TestLine(args, __source__)
  end
end

testline_requested(_) = false
testline_requested(_::Live.TestLine) = true

text = ""
function editorchange(editortext)
    try  # So errors don't crash my Blink window...
        # Everything evaluated is within this new module each iteration.
        UserCode = Module(:UserCode)

        global text, parsed
        text = editortext
        parsed = parseall(editortext)
        lastline = 1
        global outputText
        outputText = ""  # Start by clearing output each iteration
        setOutputText(1, '\n'^numlines(text))
        test_next_function = false
        test_context = nothing
        nextfunction = nothing
        run_at_next_linenode = false
        for node in parsed.args
            if isa(node, LineNumberNode)
                lastline = node.line
                if run_at_next_linenode
                    testfunction(nextfunction..., lastline, test_context)
                    run_at_next_linenode = false
                end
            end
            try
                out = Core.eval(UserCode, node)
                if test_next_function && isa(out, Function)
                    nextfunction = (lastline, node, out)
                    test_next_function = false
                    run_at_next_linenode = true
                end
                if testline_requested(out)
                    test_next_function =  true
                    test_context = out.args
                elseif out != nothing
                    setOutputText(lastline, repr(out))
                end
            catch e
                setOutputText(lastline, string(e))
            end
        end
    catch err
        println("ERROR: $err")
    end
    nothing
end
Blink.handlers(w)["editorchange"] = editorchange

function testfunction(firstline, node, f, lastline, test_context)
    # Everything evaluated here should be within this new module.
    FunctionModule = Module(:FunctionModule)
    # First, eval the context
    for e in test_context
        Core.eval(FunctionModule, e)
    end
    #println("$firstline, $node, $f, $lastline")
    global fnode = node
    global body = fnode.args[2]
    lastline = 1
    for node in body.args
        if isa(node, LineNumberNode)
            lastline = node.line
        end
        try
            out = Core.eval(FunctionModule, node)
            setOutputText(firstline + lastline-1, repr(out))
        catch e
            println("testfunction ERROR: $e")
        end
    end
end



# --- FILE API ---
# Set up dialog
js(w, Blink.JSString(""" dialog = nodeRequire('electron').remote.dialog; """))
function open_dialog(selectedfiles)
    println(selectedfiles)
    if selectedfiles == nothing || isempty(selectedfiles) || selectedfiles[1] == ""
        return
    end
    contents = read(selectedfiles[1], String)
    println(contents)
    @js_ w texteditor.setValue($contents)
end

save_dialog(args::Array) = save_dialog(args...)
function save_dialog(selectedfile, contents)
    println(selectedfile)
    if selectedfile == nothing || selectedfile == ""
        return
    end
    write(selectedfile, contents)
    println(contents)
end


# Create menus

js(w, Blink.JSString("""
    const {app, Menu} = nodeRequire('electron').remote

    function clickOpen(menuItem, browserWindow, event) {
        selectedfiles = dialog.showOpenDialog({properties: ['openFile']});
        console.log(selectedfiles)
        Blink.msg("open", selectedfiles);
    }
    function clickSave(menuItem, browserWindow, event) {
        selectedfile = dialog.showSaveDialog({});
        console.log(selectedfile)
        Blink.msg("save", [selectedfile, texteditor.getValue()]);
    }

      const template = [
        {
          label: 'File',
          submenu: [
            {label: 'Open', click: clickOpen, accelerator:'CommandOrControl+O'},
            {type: 'separator'},
            {label: 'Save', click: clickSave, accelerator:'CommandOrControl+S' },
          ]
        },
        {
          label: 'Edit',
          submenu: [
            {role: 'undo'},
            {role: 'redo'},
            {type: 'separator'},
            {role: 'cut'},
            {role: 'copy'},
            {role: 'paste'},
            {role: 'pasteandmatchstyle'},
            {role: 'delete'},
            {role: 'selectall'}
          ]
        },
        {
          label: 'View',
          submenu: [
            {role: 'reload'},
            {role: 'forcereload'},
            {role: 'toggledevtools'},
            {type: 'separator'},
            {role: 'resetzoom'},
            {role: 'zoomin'},
            {role: 'zoomout'},
            {type: 'separator'},
            {role: 'togglefullscreen'}
          ]
        },
        {
          role: 'window',
          submenu: [
            {role: 'minimize'},
            {role: 'close'}
          ]
        },
        {
          role: 'help',
          submenu: [
            {
              label: 'Learn More',
              click () { require('electron').shell.openExternal('https://electronjs.org') }
            }
          ]
        }
      ]

      if (process.platform === 'darwin') {
        template.unshift({
          label: app.getName(),
          submenu: [
            {role: 'about'},
            {type: 'separator'},
            {role: 'services', submenu: []},
            {type: 'separator'},
            {role: 'hide'},
            {role: 'hideothers'},
            {role: 'unhide'},
            {type: 'separator'},
            {role: 'quit'}
          ]
        })

        // Edit menu
        template[2].submenu.push(
          {type: 'separator'},
          {
            label: 'Speech',
            submenu: [
              {role: 'startspeaking'},
              {role: 'stopspeaking'}
            ]
          }
        )

        // Window menu
        template[4].submenu = [
          {role: 'close'},
          {role: 'minimize'},
          {role: 'zoom'},
          {type: 'separator'},
          {role: 'front'}
        ]
      }

      const menu = Menu.buildFromTemplate(template)
      Menu.setApplicationMenu(menu)
  """))
Blink.handlers(w)["save"] = save_dialog
Blink.handlers(w)["open"] = open_dialog
