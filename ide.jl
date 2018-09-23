using Blink
using DataStructures: DefaultDict

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
        width: 50%;
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

function setOutputText(linesdict, line, text)
    textlines = split(text, '\n')
    for l in 1:length(textlines)
        linesdict[line+l-1] = textlines[l]
    end
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
        global UserCode = Module(:UserCode)

        outputlines = DefaultDict{Int,String}("")

        global text, parsed
        text = editortext
        parsed = parseall(editortext)
        lastline = 1
        test_next_function = false
        test_context = nothing
        nextfunction = nothing
        run_at_next_linenode = false
        for node in parsed.args
            if isa(node, LineNumberNode)
                lastline = node.line
                if run_at_next_linenode
                    testfunction(nextfunction..., lastline, test_context, outputlines)
                    run_at_next_linenode = false
                end
            end
            try
                # TODO: use evalnode here
                #if isa(node, Expr) && node.head == :function
                #end
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
                    setOutputText(outputlines, lastline, repr(out))
                end
            catch e
                setOutputText(outputlines, lastline, string(e))
            end
        end
        # -- UPDATE OUTPUT AT END OF THE LOOP --

        # Must use @js_ since no return value required. (@js hangs)
        #@js_ w outputarea.replaceRange($text, CodeMirror.Pos($start, 0), CodeMirror.Pos($finish, 0))
        #println("after: $outputlines")
        maxline = max(length(editortext), maximum(keys(outputlines)))
        outputText = join([outputlines[i] for i in 1:maxline], "\n")
        outputText = rstrip(outputText)
        @js_ w outputarea.setValue($outputText)
    catch err
        println("ERROR: $err")
    end
    nothing
end
Blink.handlers(w)["editorchange"] = editorchange

function import_names_into(destmodule, srcmodule)
    fullsrcname = join(fullname(srcmodule), ".")
    for n in names(srcmodule, all=true)
        if !(n in [Symbol("#eval"), Symbol("#include"), :eval, :include])
            Core.eval(destmodule, :($n = Main.$(nameof(srcmodule)).$n))
        end
    end
end
function testfunction(firstline, node, f, lastline, test_context, outputlines)
    # Everything evaluated here should be within this new module.
    FunctionModule = Module(:(FunctionModule))
    import_names_into(FunctionModule, UserCode)
    # First, eval the context
    for e in test_context
        Core.eval(FunctionModule, e)
    end
    #println("$firstline, $node, $f, $lastline")
    global fnode = node
    global body = fnode.args[2]
    try
        evalblock(FunctionModule, body, firstline, 1, outputlines)
    catch e
        println("testfunction ERROR: $e")
        setOutputText(outputlines, firstline+lastline-1, repr(e))
        return
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

# Weird code stuff
function handle_for_loop(FunctionModule, node, firstline, lastline, outputlines)
    global fornode = node
    iterspec_node = node.args[1]
    body = node.args[2]
    # Modify the iteration specification variable's name to a temp.
    itervariable = iterspec_node.args[1]
    # Start interpreting the for-loop
    try
        iterspec = Core.eval(FunctionModule, iterspec_node.args[2])  # just the range itself
        temp = Base.iterate(iterspec)
        iteration_outputs = []
        while temp != nothing
            loopoutputs = DefaultDict{Int,String}("")
            Core.eval(FunctionModule, :($itervariable = $(Expr(:quote, temp[1]))))
            try
                lastline = evalblock(FunctionModule, body, firstline, lastline, loopoutputs)
            catch e
                push!(iteration_outputs, loopoutputs)
                display_loop_lines(outputlines, iteration_outputs)
                throw(e)
            end
            push!(iteration_outputs, loopoutputs)
            temp = Base.iterate(iterspec, temp[2])
        end
        display_loop_lines(outputlines, iteration_outputs)
    catch e
        # TODO: Simplify this error handling by having a global line counter & _maybe_ even a global outputlines.
        setOutputText(outputlines, firstline+lastline-1, repr(e))
        # TODO: Re-evaluate this decision.. maybe there's no reason to rethrow here at all!
        #   Maybe it's _cool_ that it keeps evaluating as best it can! Something to consider.
        #   Also, removing these would be easier, i think.
        #   Oooh, the coolest thing would be like, to make the rest of the output red or something!
        throw(e)
    end
end
function handle_while_loop(FunctionModule, node, firstline, outputlines)
    global whilenode = node
    test = node.args[1]
    body = node.args[2]
    iteration_outputs = []
    lastline = 1
    while Core.eval(FunctionModule, test)
        loopoutputs = DefaultDict{Int,String}("")
        try
            lastline = evalblock(FunctionModule, body, firstline, lastline, loopoutputs)
        catch e
            push!(iteration_outputs, loopoutputs)
            display_loop_lines(outputlines, iteration_outputs)
            throw(e)
        end
        push!(iteration_outputs, loopoutputs)
    end
    display_loop_lines(outputlines, iteration_outputs)
end
function display_loop_lines(outputlines, iteration_outputs)
    # For now, just append each iteration's outputs on the line.
    lineouts = DefaultDict{Int, Array{String}}(()->[])
    for outputs in iteration_outputs
        for (l, s) in outputs
            push!(lineouts[l], s)
        end
    end
    for (line, outs) in lineouts
        setOutputText(outputlines, line, join(outs, ", "))
    end
end

function evalnode(FunctionModule, node, firstline, lastline, outputlines)
    try
        if isa(node, LineNumberNode)
            return node.line
        end
        # Handle special-cases
        if isa(node, Expr) && node.head == :block
            evalblock(FunctionModule, node, firstline, lastline, outputlines)
        elseif isa(node, Expr) && node.head == :while
            handle_while_loop(FunctionModule, node, firstline, outputlines)
        elseif isa(node, Expr) && node.head == :for
            handle_for_loop(FunctionModule, node, firstline, lastline, outputlines)
        elseif isa(node, Expr) && node.head == :if
            handle_if(FunctionModule, node, firstline, lastline, outputlines)
        else
            out = Core.eval(FunctionModule, node)
            setOutputText(outputlines, firstline + lastline-1, repr(out))
        end
    catch e
        setOutputText(outputlines, firstline+lastline-1, repr(e))
        throw(e)
    end
end
function evalblock(FunctionModule, blocknode, firstline, lastline, outputlines)
    for node in blocknode.args
        global gnode = node
        lastline = evalnode(FunctionModule, node, firstline, lastline, outputlines)
        global pnode = node
    end
    return lastline
end

function handle_if(FunctionModule, node, firstline, offsetline, outputlines)
    global ifnode = node
    test = node.args[1]
    trueblock = node.args[2]
    restblock = if (length(node.args) > 2) node.args[3] else nothing end
    testval = Core.eval(FunctionModule, test)
    #setOutputText(outputlines, firstline, repr(testval))
    if testval
        evalnode(FunctionModule, trueblock, firstline, offsetline, outputlines)
    elseif restblock != nothing && restblock.head == :elseif
        handle_if(FunctionModule, restblock, firstline, offsetline, outputlines)
    else
        evalnode(FunctionModule, restblock, firstline, offsetline, outputlines)
    end
end
