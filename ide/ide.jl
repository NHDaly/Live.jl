module LiveIDE

using Blink
using DataStructures: DefaultDict

using Live # Define the Live macro for use in the IDE
Live.@script(false)

include("parsefile.jl")

cd(@__DIR__)

global bg_window = nothing
function new_window()
    cd(@__DIR__)  # Need to do this every time to make sure the resources exist.

    global bg_window
    if bg_window == nothing
        bg_window = Window(Dict(:show=>false), async=false)

        # To allow using JQuery in electron:
        # https://electronjs.org/docs/faq#i-can-not-use-jqueryrequirejsmeteorangularjs-in-electron
        js(bg_window, Blink.JSString("""
            window.nodeRequire = require;
            window.nodeExports = window.exports;
            window.nodeModule = window.module;
            delete window.require;
            delete window.exports;
            delete window.module;
         """))

         set_up_app_menu(bg_window)
    end
    w = Window(async=false)
    title(w, "untitled")
    #tools(w)

    # To allow using JQuery in electron:
    # https://electronjs.org/docs/faq#i-can-not-use-jqueryrequirejsmeteorangularjs-in-electron
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
           <textarea id="text-editor">using Live\nLive.@script()\n\n</textarea>
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

    # Set up save and open functions
    set_up_window_menu(w)

    # (globalFilepath is set when saving/loading files. Passing it allows cd() before executing.)
    @js w texteditor.on("update",
        (cm) -> (Blink.msg("editorchange", [cm.getValue(), globalFilepath]);
                 console.log("sent msg to julia!");))

    Blink.handle(w, "editorchange") do (txt, filepath)
        editorchange(w, filepath, txt)
    end
    #Blink.handlers(w)["editorchange"] = (args...)->editorchange(w, args...)
    # Do an initial run.
    @js w Blink.msg("editorchange", [texteditor.getValue(), globalFilepath]);
end

# User code parsing + eval
numlines(str) = 1+count(c->c=='\n', str)

function setOutputText(linesdict, line, text)
    textlines = split(text, '\n')
    for l in 1:length(textlines)
        linesdict[line+l-1] = textlines[l]
    end
end

is_function_testline_request(_) = false
is_function_testline_request(_::Live.TestLine) = true

function editorchange(w, globalFilepath, editortext)
    #try  # So errors don't crash my Blink window...
        # Everything evaluated is within this new module each iteration.
        # TODO: change this to :Main once the Live module is in a real package!
        global UserCode = Module(:LiveMain, true)
        setparent!(UserCode, UserCode)
        @eval UserCode include(fname::AbstractString) = Main.Base.include(@__MODULE__, fname)


        # Automatically import Live to allow users to enable/disable Live mode:
        Core.eval(UserCode, :(import Live))

        # TODO: eventually each window should probably have its own julia process
        if !isempty(globalFilepath)
            cd(dirname(globalFilepath))  # Execute the code starting from the right file
            @eval UserCode macro __FILE__() return $globalFilepath end
        end

        outputlines = DefaultDict{Int,String}("")

        global scriptmode_enabled = false

        global text = editortext
        global parsed = parseall(editortext)
        try
            # TODO: ooh, we should also probably swipe stdout so that it also
            # writes to the app. Perhaps in a different type of output div.
            evalblock(UserCode, parsed, 1, 1, outputlines; toplevel=true, keepgoing=true)
        catch end

        # -- Display output in js window after everything is done --
        maximum_or_default(itr, default) = isempty(itr) ? default : maximum(itr)

        # Must use @js_ since no return value required. (@js hangs)
        #@js_ w outputarea.replaceRange($text, CodeMirror.Pos($start, 0), CodeMirror.Pos($finish, 0))
        #println("after: $outputlines")
        maxline = max(length(editortext), maximum_or_default(keys(outputlines),0))
        outputText = join([outputlines[i] for i in 1:maxline], "\n")
        outputText = rstrip(outputText)
        @js_ w outputarea.setValue($outputText)
    #catch err
        #println("ERROR: $err")
    #end
    nothing
end

const LIVE_SCRIPT_TRIGGER = :(Live.@script).args[1]
const LIVE_TEST_TRIGGER = :(Live.@test).args[1]
const LIVE_TESTFILE_TRIGGER = :(Live.@testfile).args[1]
const LIVE_TESTED_TRIGGER = :(Live.@tested).args[1]

function evalnode(FunctionModule, node, firstline, latestline, outputlines;
                    toplevel=false, keepgoing=false, blocknode_iter=nothing)
    global gnode = node
    global scriptmode_enabled
    try
        if isa(node, LineNumberNode)
            return node.line
        end
        # Handle the Live api:
        if isa(node, Expr) && node.head == :macrocall
            if node.args[1] == LIVE_SCRIPT_TRIGGER
                scriptmode_settings = Core.eval(FunctionModule, node)::Live.ScriptLine
                scriptmode_enabled = scriptmode_settings.enabled
                setOutputText(outputlines, firstline + latestline-1, "Script Mode: $(scriptmode_enabled)")
                return latestline
            elseif node.args[1] == LIVE_TEST_TRIGGER
                testline = Core.eval(FunctionModule, node)::Live.TestLine
                # For @Live.test lines, live-test the next function
                #  within the specified Test Context.
                return handle_live_test_line(FunctionModule, firstline, latestline, testline, blocknode_iter, outputlines, toplevel, keepgoing)
            elseif node.args[1] == LIVE_TESTFILE_TRIGGER
                testfile = Core.eval(FunctionModule, node)::Live.TestFileLine
                return handle_live_test_file(FunctionModule, firstline, latestline, testfile, blocknode_iter, outputlines, toplevel, keepgoing)
            elseif node.args[1] == LIVE_TESTED_TRIGGER
            end
        end
        if !scriptmode_enabled
            return latestline
        end

        # Handle special-cases for parsed structure
        if isa(node, Expr) && node.head == :block
            latestline = evalblock(FunctionModule, node, firstline, latestline, outputlines)
        elseif isa(node, Expr) && node.head == :while
            handle_while_loop(FunctionModule, node, firstline, outputlines)
        elseif isa(node, Expr) && node.head == :for
            handle_for_loop(FunctionModule, node, firstline, latestline, outputlines)
        elseif isa(node, Expr) && node.head == :if
            handle_if(FunctionModule, node, firstline, latestline, outputlines)
        elseif isa(node, Expr) && node.head == :module
            handle_module(FunctionModule, node, firstline, latestline, outputlines)
        elseif isa(node, Expr) && node.head == :struct
            if toplevel != true
                #showerror(stdout, "NATHAN", backtrace(), backtrace=true)
                error("""syntax: "struct" expression not at top level""")
            end
            handle_struct(FunctionModule, node, firstline, latestline, outputlines)
        else
            out = Core.eval(FunctionModule, node)
            setOutputText(outputlines, firstline + latestline-1, repr(out))
        end
    catch er
        #showerror(stdout, er, catch_backtrace(), backtrace=true)
        setOutputText(outputlines, firstline+latestline-1, sprint(showerror, er))
        if !keepgoing
            rethrow(er)
        end
    end
end
function evalblock(FunctionModule, blocknode, firstline, latestline, outputlines;
                    toplevel=false, keepgoing=false)
    # Track whether Live.@script() is enabled
    global scriptmode_enabled
    # These are for implementing Live.@test lines, since they're a non-standard
    # macro (since they affect the "next" line, which a macro isn't really
    # supposed to do.)
    nodeiter = Iterators.Stateful(blocknode.args);
    while !isempty(nodeiter)
        node = popfirst!(nodeiter)
        # Note that
        latestline = evalnode(FunctionModule, node, firstline, latestline,
                              outputlines; toplevel=toplevel, keepgoing=keepgoing,
                              blocknode_iter=nodeiter)
    end
    return latestline
end

# ------------------------------------------------------------------------------
# Live testing functions

function handle_live_test_line(FunctionModule, firstline, latestline, testline, blocknode_iter, outputlines, toplevel, keepgoing)
    global scriptmode_enabled
    test_context = testline.args
    if blocknode_iter != nothing
        latestline, node = pop_next_matching_node(is_function_node, blocknode_iter, latestline)
        if (node == nothing)
            setOutputText(outputlines, firstline+latestline-1, "ERROR: Live.@test must precede a function definition.")
            return latestline
        end
        # Always enable script mode while executing a Live.@test function
        prev_scriptmode = scriptmode_enabled
        scriptmode_enabled = true
        livetest_function(FunctionModule,
                          if toplevel latestline else firstline end,
                          if toplevel 1 else latestline end,
                          node, test_context, outputlines)
        scriptmode_enabled = prev_scriptmode
    end
end
function pop_next_matching_node(node_matcher, blocknode_iter, latestline)
    # Get the next node, which should be a function. (If it's a LineNumberNode, consume it and continue.)
    while !isempty(blocknode_iter)
        node = popfirst!(blocknode_iter)
        if node_matcher(node)
            return (latestline, node)
        elseif isa(node, LineNumberNode)
            latestline = node.line
        else
            # Next node wasn't a function. Give up on this.
            return (latestline, nothing)
            #latestline = evalnode(FunctionModule, node, firstline, latestline,
            #                      outputlines; toplevel=toplevel, keepgoing=keepgoing,
            #                      blocknode_iter=blocknode_iter)
        end
    end
    return (latestline, nothing)
end
function livetest_function(ScopeModule, firstline, latestline, node, test_context, outputlines)
    global fnode = node
    fname = String(fnode.args[1].args[1])
    fargs = fnode.args[1].args[2:end]
    body = fnode.args[2]

    # Display the function signature
    fsig = "$ScopeModule.$(fnode.args[1])"
    setOutputText(outputlines, firstline+latestline-1, fsig)

    # Everything evaluated here should be within this new module.
    TestContextModule = deepcopy(ScopeModule)
    # First, eval the context
    for expr in test_context
        Core.eval(TestContextModule, expr)
    end

    try
        # TODO: it would be nice to *indent* the output inside a block.
        evalnode(TestContextModule, body, firstline, latestline, outputlines)

        # Finally, eval the function so it's defined for the rest of the code
        Core.eval(ScopeModule, node)
    catch er
        setOutputText(outputlines, firstline+latestline-1, "$fname: "* sprint(showerror, er))
        return
    end
end

is_function_node(n) = (isa(n, Expr) && n.head == :function# ||
    #(n.head == :(=) && isa(n.args[1], Expr) && n.args[1].head == :call)
)

function handle_live_test_file(FunctionModule, firstline, latestline, testfile, blocknode_iter, outputlines, toplevel, keepgoing)
    global scriptmode_enabled
    liveline = firstline+latestline
    if blocknode_iter != nothing
        latestline, node = pop_next_matching_node(is_function_node, blocknode_iter, latestline)
        if (node == nothing)
            setOutputText(outputlines, liveline, "ERROR: Live.@testfile must precede a function definition.")
            return latestline
        end
        functionname = node.args[1].args[1]
        fargs = node.args[1].args[2:end]
        # TODO: Support more than one context
        file = Core.eval(FunctionModule, testfile.files[1])  # Eval in case the file is built dynamically.
        test_context = create_test_context_from_file(file, functionname, fargs)
        if test_context == nothing
            setOutputText(outputlines, liveline, "ERROR: file does not contain a matching Live.@tested($functionname) block")
            return latestline
        end
        # Set output text to show the test:
        setOutputText(outputlines, liveline, "Testing: $(join(test_context, ", "))")

        # Always enable script mode while executing a Live.@test function
        prev_scriptmode = scriptmode_enabled
        scriptmode_enabled = true
        livetest_function(FunctionModule,
                          if toplevel latestline else firstline end,
                          if toplevel 1 else latestline end,
                          node, test_context, outputlines)
        scriptmode_enabled = prev_scriptmode
    end
end
function create_test_context_from_file(file, functionname, fargs)
    #@show file
    testfile_block = parseall(read(file, String))
    testfile_block == nothing && return nothing
    TestFileModule = Module(:TestFile, true)
    setparent!(TestFileModule, TestFileModule)
    @eval TestFileModule include(fname::AbstractString) = Main.Base.include(@__MODULE__, fname)
    Core.eval(TestFileModule, :(import Live))

    cwd = pwd()
    cd(dirname(file))
    try  # finally to cd back to cwd
        nodeiter = Iterators.Stateful(testfile_block.args);
        while !isempty(nodeiter)
            node = popfirst!(nodeiter)
            if isa(node, Expr) && node.head == :macrocall
                if node.args[1] == LIVE_SCRIPT_TRIGGER ||
                    node.args[1] == LIVE_TESTFILE_TRIGGER
                    node.args[1] == LIVE_TEST_TRIGGER
                    # Skip the other Live.@... macros when running a test file!
                    continue
                elseif node.args[1] == LIVE_TESTED_TRIGGER
                    testedline = eval(node)::Live.TestedLine
                    if testedline.functionname == functionname
                        not_linenumber(maybelinenumbernode) = !(maybelinenumbernode isa LineNumberNode)
                        _, testnode = pop_next_matching_node(not_linenumber, nodeiter, 1)
                        if testnode == nothing
                            #println("SKIPPING NODE")
                            continue
                        end
                        # Copy the module and override its definition of the function
                        TestModuleCopy = deepcopy(TestFileModule)
                        args_channel = Channel(1)
                        fakefunc(args...) = put!(args_channel, args)  # Notify caller
                        @eval TestModuleCopy $functionname = $fakefunc
                        # Now evaluate the test block, and catch the first call!
                        @async try
                            Core.eval(TestModuleCopy, testnode)
                        catch e
                            #@show e
                        finally
                            put!(args_channel, nothing)
                        end
                        # Wait until the args are passed!
                        testargs = take!(args_channel)
                        #@show testargs
                        if (testargs == nothing)
                            return nothing
                        end
                        return Tuple(:($arg=$val) for (arg,val) in zip(fargs, testargs))
                    end
                else
                    evalnode(TestFileModule, node, 1, 1, Dict(); toplevel=true)
                end
            end
        end
    catch e
        #showerror(stdout, e, catch_backtrace(), backtrace=true)
    finally
        cd(cwd)
    end
    return nothing
end
# ------------------------------------------------------------------------------
# Handling special-cases for parsed structure

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
                latestline = evalnode(FunctionModule, body, firstline, latestline, loopoutputs)
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
        setOutputText(outputlines, firstline+latestline-1, sprint(showerror, er))
        # TODO: Re-evaluate this decision.. maybe there's no reason to rethrow here at all!
        #   Maybe it's _cool_ that it keeps evaluating as best it can! Something to consider.
        #   Also, removing these would be easier, i think.
        #   Oooh, the coolest thing would be like, to make the rest of the output red or something!
        rethrow(e)
    end
end
function handle_while_loop(FunctionModule, node, firstline, outputlines)
    global whilenode = node
    test = node.args[1]
    body = node.args[2]
    iteration_outputs = []
    latestline = 1
    # TODO: Add a manual depth-check so we don't freeze the program with a while true end.
    while Core.eval(FunctionModule, test)
        loopoutputs = DefaultDict{Int,String}("")
        try
            latestline = evalnode(FunctionModule, body, firstline, latestline, loopoutputs)
        catch e
            push!(iteration_outputs, loopoutputs)
            display_loop_lines(outputlines, iteration_outputs)
            rethrow(e)
        end
        push!(iteration_outputs, loopoutputs)
    end
    display_loop_lines(outputlines, iteration_outputs)
end
function display_loop_lines(outputlines, iteration_outputs)
    global iterouts = iteration_outputs
    all_lines = keys(merge(iteration_outputs...))
    lmin, lmax = minimum(all_lines), maximum(all_lines)
    len = lmax - lmin + 1
    out_array = fill("", (len, length(iteration_outputs)))
    for (i,outputs) in enumerate(iteration_outputs)
        for (l, s) in outputs
            out_array[l-lmin+1, i] = s
        end
    end
    for i in 1:size(out_array)[2]
        maxsize = maximum(length.(out_array[:,i]))
        out_array[:,i] .= rpad.(out_array[:,i], maxsize)
    end
    for i in 1:size(out_array)[1]
        line = i+lmin-1
        val = join(out_array[i,:], " | ")
        setOutputText(outputlines, i+lmin-1, join(out_array[i,:], " | "))
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
        evalnode(FunctionModule, trueblock, firstline, offsetline, outputlines)
    elseif restblock != nothing && restblock.head == :elseif
        handle_if(FunctionModule, restblock, firstline, offsetline, outputlines)
    else
        evalnode(FunctionModule, restblock, firstline, offsetline, outputlines)
    end
end

function handle_module(FunctionModule, node, firstline, offsetline, outputlines)
    global modulenode = node
    module_name = node.args[2]
    NewModule = Module(module_name, true)
    setparent!(NewModule, FunctionModule)
    @eval NewModule include(fname::AbstractString) = Main.Base.include(@__MODULE__, fname)
    restblock = node.args[3]
    evalnode(NewModule, restblock, offsetline, 1, outputlines; toplevel=true)
    #setOutputText(outputlines, firstline+offsetline-1, string(module_name))
    # Now add the created module into FunctionModule:
    Core.eval(FunctionModule, :($module_name = $NewModule))
end

function handle_struct(FunctionModule, node, firstline, offsetline, outputlines)
    global structnode = node
    # Eval the struct
    out = Core.eval(FunctionModule, node)
    # Assuming struct definition has no output (like usual),
    # let's make the output be: `dump(StructName)`
    # (handle parametric types)
    if out == nothing
        parametric = node.args[2] isa Expr
        structName = (parametric ? node.args[2].args[1] : node.args[2])
        dumpedOutput = Core.eval(FunctionModule, quote
            sprint(io->dump(io, $parametric ? $structName.body : $structName))
        end)
        setOutputText(outputlines, firstline+offsetline-1, dumpedOutput)
    else
        setOutputText(outputlines, firstline+offsetline-1, repr(out))
    end
end

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
    for m in usings(srcmodule)
        full_using_name = Expr(:., fullname(m)...)
        Core.eval(destmodule, Expr(:using, full_using_name))
    end
    for n in names(srcmodule, all=true, imported=true)
        # don't copy itself into itself; don't copy `include`, define it below instead
        if n != nameof(destmodule) && n != :include
            Core.eval(destmodule, :($n = $(Core.eval(srcmodule, n))))
        end
    end
    @eval destmodule include(fname::AbstractString) = Main.Base.include(@__MODULE__, fname)
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

function set_up_app_menu(w)
    # Set handlers to be called from javascript
    Blink.handlers(w)["new"] = (_)->new_window()

    # Javascript: Create app menus
    js(w, Blink.JSString("""
        const {app, Menu, BrowserWindow, dialog, ipcMain} = nodeRequire('electron').remote

        function clickNew(menuItem, browserWindow, event) {
            console.log("clickNew");
            Blink.msg("new", []);
        }
        function clickOpen(menuItem, browserWindow, event) {
            let focusedWindow = BrowserWindow.getFocusedWindow();
            focusedWindow.webContents.send('file-open');
        }
        function clickSave(menuItem, browserWindow, event) {
            let focusedWindow = BrowserWindow.getFocusedWindow();
            focusedWindow.webContents.send('file-save');
        }
        function clickSaveAs(menuItem, browserWindow, event) {
            let focusedWindow = BrowserWindow.getFocusedWindow();
            focusedWindow.webContents.send('file-save-as');
        }

        const template = [
          {
            label: 'File',
            submenu: [
              {label: 'New', click: clickNew, accelerator:'CommandOrControl+N'},
              {label: 'Open', click: clickOpen, accelerator:'CommandOrControl+O'},
              {type: 'separator'},
              {label: 'Save', click: clickSave, accelerator:'CommandOrControl+S' },
              {label: 'Save As...', click: clickSaveAs, accelerator:'CommandOrControl+Shift+S' },
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
end

function set_up_window_menu(w)
    # --- FILE API ---
    # Set up dialog
    function open_file(selectedfiles)
        println("open_file: $selectedfiles")
        if selectedfiles == nothing || isempty(selectedfiles) || selectedfiles[1] == ""
            return
        end
        contents = read(selectedfiles[1], String)
        @js_ w texteditor.setValue($contents)
        title(w, selectedfiles[1])
    end

    save_file(args::Array) = save_file(args...)  # js sends args as an array
    function save_file(selectedfile, contents)
        println(selectedfile)
        if selectedfile == nothing || selectedfile == ""
            return
        end
        write(selectedfile, contents)
        title(w, selectedfile)
    end

    # Set handlers to be called from javascript
    Blink.handlers(w)["open"] = open_file
    Blink.handlers(w)["save"] = save_file

    # Javascript: Handle save and open dialog messages
    js(w, Blink.JSString("""
        // I don't really understand the difference between these...
        const {dialog} = nodeRequire('electron').remote
        const {ipcRenderer} = nodeRequire('electron')

        globalFilepath = ""

        function handle_open() {
            var selectedfiles = dialog.showOpenDialog({properties: ['openFile'],
                                                       defaultPath: globalFilepath});
            console.log(selectedfiles);
            if (selectedfiles !== undefined) {
                Blink.msg("open", selectedfiles);
                globalFilepath = selectedfiles[0];
            }
        }
        function handle_save() {
            if (globalFilepath == "") {
                handle_save_as();
            } else {
                Blink.msg("save", [globalFilepath, texteditor.getValue()]);
            }
        }
        function handle_save_as() {
            var selectedfile = dialog.showSaveDialog({defaultPath: globalFilepath});
            console.log(selectedfile);
            if (selectedfile !== undefined) {
                Blink.msg("save", [selectedfile, texteditor.getValue()]);
                globalFilepath = selectedfile;
            }
        }

        // Set up handlers from the main process to handle Menu events:
        ipcRenderer.on('file-open', (event, message) => {
            handle_open();
        })
        ipcRenderer.on('file-save', (event, message) => {
            handle_save();
        })
        ipcRenderer.on('file-save-as', (event, message) => {
            handle_save_as();
        })
        console.log(ipcRenderer);
    """))
end
end

LiveIDE.new_window()
