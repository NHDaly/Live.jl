@eval Live begin
    function reset_testfuncs()
        global testthunks = Function[]
    end

    # Run the function!
    function testcall(fcall, file::$LiveIDEFile, line)
        quote
            function live_test()
                try
                    $(esc(fcall))
                catch e
                    push!($($LiveEval).ctx.outputs, ($line => e))
                end
            end
            push!($Live.testthunks, live_test)
            nothing
        end
    end

    # Include the testfile
    function testfile_call(files, file::$LiveIDEFile, line)
        escfiles = [esc(f) for f in files]
        quote
            for f in [$(escfiles...)]
                push!($Live.testthunks, ()->begin
                    try
                        return (@__MODULE__).include(f)
                    catch le
                        if le isa LoadError
                            e = le.error
                            push!($($LiveEval).ctx.outputs, ($line => e))
                        end
                    end
                 end)
            end
        end
    end

    # Toggle script mode
    function script_call(enable, file::$LiveIDEFile, line)
        # TODO
    end
end
