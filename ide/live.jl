@eval Live begin
    function reset_testfuncs()
        global testthunks = Function[]
    end

    # Run the function!
    function testcall(fcall, linenode::$LiveIDEFile)
        quote
            function live_test()
                $(esc(fcall))
            end
            push!($Live.testthunks, live_test)
            nothing
        end
    end

    # Include the testfile
    function testfile_call(files, linenode::$LiveIDEFile)
        escfiles = [esc(f) for f in files]
        quote
            for f in [$(escfiles...)]
                push!($Live.testthunks, ()->begin
                 @show f
                 (@__MODULE__).include(f); nothing end)
            end
        end
    end

    # Toggle script mode
    function script_call(enable, linenode::$LiveIDEFile)
        # TODO
    end
end
