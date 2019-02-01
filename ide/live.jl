@eval Live begin
    function reset_testfuncs()
        global testthunks = Function[]
    end

    # Run the function!
    function testcall(fcall, linenode)
        quote
            function live_test()
                $(esc(fcall))
            end
            push!($Live.testthunks, live_test)
            nothing
        end
    end

    # Include the testfile
    function testfile_call(files)
        escfiles = [esc(f) for f in files]
        quote
            for f in [$(escfiles...)]
                push!(Live.testthunks, ()->begin
                 @show f
                 include(f); nothing end)
            end
        end
    end

    # Toggle script mode
    function script_call(enable)
        # TODO
    end
end
