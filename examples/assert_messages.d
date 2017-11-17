/+ dub.sdl:
    name "composer_examples_assert_messages"
    dependency "composer" path="../"
    targetType "executable"
+/
module examples.assert_messages;

import composer.composer;

private char[1024 * 4] msgBuffer;

/**
Creates a thread-local composer, that will be destroyed
automatically when it's exceeded its useful lifespan.

Because of thread-local storage, there is only one point
of access to the message buffer. This is best used when
there is a need to compose assert messages at runtime in
methods that must not allocate memory.
*/
@property auto getComposer()
{
    return Composer!char(msgBuffer[]);
}

void main()
{
    func();
}

@safe @nogc func() nothrow
{
    //dfmt off
    assert(false, getComposer.write("This is a message with numbers: ", 12,
                                 ", and pointers: ", ()@trusted {return cast(void*) 0xDEADBEEF;}())
                             .message);
    //dmft on
}
