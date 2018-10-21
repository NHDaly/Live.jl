using Live
Live.@script()


x = 5

# You can hide lines that you don't 
# want to execute live inside this:
Live.@script(false)

x = 6

Live.@script()

x  # Still outputs 5
