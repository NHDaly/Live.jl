using Blink
using DataStructures: DefaultDict

include("parsefile.jl")

cd(@__DIR__)
w = Window(async=false)
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

load!(w, "frameworks/jquery-3.3.1.js", async=true)

# Load codemirror
load!(w, "frameworks/codemirror-5.40.0/lib/codemirror.js", async=false)
load!(w, "frameworks/codemirror-5.40.0/lib/codemirror.css", async=true)
# Set up for julia:
load!(w, "frameworks/codemirror-5.40.0/mode/julia/julia.js", async=true)


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

is_function_testline_request(_) = false
is_function_testline_request(_::Live.TestLine) = true

text = ""
function editorchange(editortext)
    try  # So errors don't crash my Blink window...
        # Everything evaluated is within this new module each iteration.
        global UserCode = Module(:UserCode)

        outputlines = DefaultDict{Int,String}("")

        global text, parsed
        text = editortext
        parsed = parseall(editortext)
        latestline = 1
        test_next_function = false
        test_context = nothing
        for node in parsed.args
            if isa(node, LineNumberNode)
                latestline = node.line
            end
            try
                # TODO: use evalblock here
                #if isa(node, Expr) && node.head == :function
                #end
                out = Core.eval(UserCode, node)
                if isa(node, Expr) && node.head == :struct && out == nothing
                    println("struct: $node")
                    # Assuming struct definition has no output (like usual),
                    # let's make the output be: `dump(StructName)`
                    # (handle parametric types)
                    parametric = node.args[2] isa Expr
                    structName = (parametric ? node.args[2].args[1] : node.args[2])
                    dumpedOutput = Core.eval(UserCode, quote
                        sprint(io->dump(io, $parametric ? $structName.body : $structName))
                    end)
                    setOutputText(outputlines, latestline, dumpedOutput)
                end
                if test_next_function && isa(out, Function)
                    test_next_function = false
                    livetest_block(UserCode, latestline, node, test_context, outputlines, fname=repr(out))
                elseif is_function_testline_request(out)
                    test_next_function =  true
                    test_context = out.args
                elseif out != nothing
                    setOutputText(outputlines, latestline, repr(out))
                end
            catch e
                setOutputText(outputlines, latestline, string(e))
            end
        end
        # -- UPDATE OUTPUT AT END OF THE LOOP --
        maximum_or_default(itr, default) = isempty(itr) ? default : maximum(itr)

        # Must use @js_ since no return value required. (@js hangs)
        #@js_ w outputarea.replaceRange($text, CodeMirror.Pos($start, 0), CodeMirror.Pos($finish, 0))
        #println("after: $outputlines")
        maxline = max(length(editortext), maximum_or_default(keys(outputlines),0))
        outputText = join([outputlines[i] for i in 1:maxline], "\n")
        outputText = rstrip(outputText)
        @js_ w outputarea.setValue($outputText)
    catch err
        println("ERROR: $err")
        rethrow(err)
    end
    nothing
end
Blink.handlers(w)["editorchange"] = editorchange


# ------------ MODULES: Custom implementation of deepcopy(m::Module) ---------------------------
import Base: deepcopy
function deepcopy(m::Module)
    global sourceModule=m
    m2 = Module(nameof(m), true)
    import_names_into(m2, m)
    setparent!(m2, parentmodule(m))
    return m2
end

# Note: this is a shallow copy! (Only imports the _names_ -- shares refs)
function import_names_into(destmodule, srcmodule)
    fullsrcname = Meta.parse(join(fullname(srcmodule), "."))
    for n in names(srcmodule, all=true, imported=true)
        if n != nameof(destmodule)  # don't copy itself into itself
            Core.eval(destmodule, :($n = $(Core.eval(srcmodule, n))))
        end
    end
    for m in usings(srcmodule)
        Core.eval(destmodule, :($(nameof(m)) = $(Core.eval(srcmodule, m))))
    end
end

usings(m::Module) =
    ccall(:jl_module_usings, Array{Module,1}, (Any,), m)

# EWWWWWWWW, this is super hacky. There's no way (that i can find) to set the parent
# of a module, so here we're depending on the structure of the jl_module_t struct
# to allow writing a new parent over it.
setparent!(m::Module, p::Module) =
    unsafe_store!(Ptr{_Module2}(pointer_from_objref(m)),
                   _Module2(nameof(m), p), 1)
struct _Module2
    name
    parent
end

# ------------------------------------------------------------------------------

function livetest_block(ScopeModule, firstline, node, test_context, outputlines; fname = nothing)
    # Everything evaluated here should be within this new module.
    TestContextModule = deepcopy(ScopeModule)
    # First, eval the context
    for e in test_context
        Core.eval(TestContextModule, e)
    end
    global fnode = node
    global body = fnode.args[2]
    try
        evalblock(TestContextModule, body, firstline, 1, outputlines)
    catch er
        setOutputText(outputlines, firstline,
                (fname != nothing ? fname*": " : "") *
                    sprint(showerror, er))
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
function handle_for_loop(FunctionModule, node, firstline, latestline, outputlines)
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
                latestline = evalblock(FunctionModule, body, firstline, latestline, loopoutputs)
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
        setOutputText(outputlines, firstline+latestline-1, repr(e))
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
    latestline = 1
    while Core.eval(FunctionModule, test)
        loopoutputs = DefaultDict{Int,String}("")
        try
            latestline = evalblock(FunctionModule, body, firstline, latestline, loopoutputs)
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

function evalblock(FunctionModule, blocknode, firstline, latestline, outputlines)
    test_next_function = false
    test_context = nothing
    try
        for node in blocknode.args
            global gnode = node

            if isa(node, LineNumberNode)
                latestline = node.line
                continue;
            end
            # Handle special-cases for parsed structure
            if isa(node, Expr) && node.head == :block
                evalblock(FunctionModule, node, firstline, latestline, outputlines)
            elseif isa(node, Expr) && node.head == :while
                handle_while_loop(FunctionModule, node, firstline, outputlines)
            elseif isa(node, Expr) && node.head == :for
                handle_for_loop(FunctionModule, node, firstline, latestline, outputlines)
            elseif isa(node, Expr) && node.head == :if
                handle_if(FunctionModule, node, firstline, latestline, outputlines)
            else
                out = Core.eval(FunctionModule, node)
                # Handle special-cases for evaluated output
                if is_function_testline_request(out)
                    # For @Live.test lines, live-test the next function
                    #  within the specified Test Context.
                    test_next_function = true
                    test_context = out.args
                elseif test_next_function && isa(out, Function)
                    test_next_function = false
                    livetest_block(FunctionModule, latestline, node, test_context, outputlines, fname=repr(out))
                end
                setOutputText(outputlines, firstline + latestline-1, repr(out))
            end
            global pnode = node
        end
        return latestline
    catch er
        println("CAUGHT: $er")
        showerror(stderr, er, catch_backtrace(); backtrace=true)
        global ernode = gnode
        setOutputText(outputlines, firstline+latestline-1, sprint(showerror, er))
        rethrow(er)  # TODO: _Do_ we want to bubble this error?
    end
end

function handle_if(FunctionModule, node, firstline, offsetline, outputlines)
    global ifnode = node
    test = node.args[1]
    trueblock = node.args[2]
    restblock = if (length(node.args) > 2) node.args[3] else nothing end
    testval = Core.eval(FunctionModule, test)
    #setOutputText(outputlines, firstline, repr(testval))
    if testval
        evalblock(FunctionModule, trueblock, firstline, offsetline, outputlines)
    elseif restblock != nothing && restblock.head == :elseif
        handle_if(FunctionModule, restblock, firstline, offsetline, outputlines)
    else
        evalblock(FunctionModule, restblock, firstline, offsetline, outputlines)
    end
end
