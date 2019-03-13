# Copyright © 2018 Nathan Daly

module LiveIDE

cd(@__DIR__)
using Pkg
Pkg.activate(".")

using Blink
using DataStructures: DefaultDict

using Live # Define the Live macro for use in the IDE
Live.@script(false)

include("parsefile.jl")
include("evaluate.jl")

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
    global current_filepath = nothing
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
            mode:  "julia",
            indentUnit: 4
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

    inflight = nothing
    Blink.handle(w, "editorchange") do (txt, filepath)
        if inflight !== nothing
            # Cancel current callback
            try schedule(inflight, CancelException(), error=true) catch end
        end
        inflight = @async editorchange(w, filepath, txt)
    end
    #Blink.handlers(w)["editorchange"] = (args...)->editorchange(w, args...)
    # Do an initial run.
    @js w Blink.msg("editorchange", [texteditor.getValue(), globalFilepath]);
end

# Signals to cancel current inflight callback.
struct CancelException end

# User code parsing + eval
numlines(str) = 1+count(c->c=='\n', str)

function setOutputText(linesdict, line, text)
    textlines = split(text, '\n')
    for l in 1:length(textlines)
        linesdict[line+l-1] = textlines[l]
    end
end

function editorchange(w, globalFilepath, editortext)
    #try  # So errors don't crash my Blink window...
        outputlines = DefaultDict{Int,String}("")

        global scriptmode_enabled = false

        try
            global text = editortext
            global parsed = parseall(editortext)
            # TODO: ooh, we should also probably swipe stdout so that it also
            # writes to the app. Perhaps in a different type of output div.
            UserCode = Module(:UserCode)
            @eval UserCode import Base: eval
            #@eval UserCode include(fname::AbstractString) = Main.Base.include(@__MODULE__, Base.relpath(fname, current_filepath))
            @eval UserCode include(fname::AbstractString) = Main.Base.include(@__MODULE__, fname)
            setparent!(UserCode, UserCode)
            outs = LiveEval.liveEval(parsed, UserCode, current_filepath)
            for (l, v) in outs
                if v === nothing continue end
                outputlines[l] *= "$v "
            end
        catch e
            if (e isa CancelException)
                return
            end
            Base.display_error(e, Base.catch_backtrace())
            #rethrow()
        end

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

# ------------ MODULES: Custom module functions ---------------------------

# EWWWWWWWW, this is super hacky. This would need to be an additional C API either to allow
# setting a module's Parent, or to allow constructing a module with a parent.
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

function set_filepath(w, path)
    title(w, path)
    global current_filepath = path
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
        set_filepath(w, selectedfiles[1])
    end

    save_file(args::Array) = save_file(args...)  # js sends args as an array
    function save_file(selectedfile, contents)
        println(selectedfile)
        if selectedfile == nothing || selectedfile == ""
            return
        end
        write(selectedfile, contents)
        set_filepath(w, selectedfile)
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
