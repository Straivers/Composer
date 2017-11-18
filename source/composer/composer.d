module composer.composer;

version(unittest) import unit_threaded;

/**
An overflow policy controls what the composer will do when
it runs out of room.
*/
enum OverflowPolicy
{
    assertFalse,
    callback,
    exception
}

enum runtime = size_t.max;

/**
The `Composer` is a configurable string joiner.

It was originally designed to be a way to allow assert
messages with runtime parameters in functions marked @nogc.
*/
struct Composer(Char, size_t buffSize = runtime, OverflowPolicy policy = OverflowPolicy.assertFalse)
{
    alias OverflowCallback = void function(ref Composer, size_t numCharsAttempted);

public:
    static if (buffSize == runtime && policy == OverflowPolicy.callback)
        @safe @nogc this(Char[] buffer, OverflowCallback callback) nothrow
        {
            _buffer = buffer;
            _overflowCallback = callback;
        }
    else static if (buffSize != runtime && policy == OverflowPolicy.callback)
        @safe @nogc this(OverflowCallback callback) nothrow
        {
            _overflowCallback = callback;
        }
    else static if (buffSize == runtime)
        @safe @nogc this(Char[] buffer) nothrow
        {
            _buffer = buffer;
        }

    /**
    Returns: The length of the message that has been written
    into the buffer so far
    */
    @safe @nogc @property size_t messageLength() const nothrow
    {
        return _nextCharIndex;
    }

    /**
    Returns: The message so far
    */
    @trusted @nogc @property immutable(Char[]) message() const nothrow
    {
        return cast(immutable(Char[])) _buffer[0 .. _nextCharIndex];
    }

    @safe @nogc @property size_t bufferSize() const nothrow
    {
        return _buffer.length;
    }

    /**
    Clears the composer of any previously written characters.
    */
    @safe @nogc void clear() nothrow
    {
        _nextCharIndex = 0;
    }

    /**
    Set the composer's buffer to `buffer`.
    This is to enable the creation of dynamic buffers.

    Params:
        buffer = The new buffer
        numCharsWritten = The number of characters already in the buffer
    */
    @safe @nogc void setBuffer(Char[] buffer, size_t numCharsWritten = 0) nothrow
    {
        _buffer = buffer;
        _nextCharIndex = numCharsWritten + 1;
    }

    /**
    Composes a message from arguments. Anything that was
    previously written to the composer will be cleared.

    If the buffer reaches capacity before the composition
    can be completed, the composer will enact the selected
    overflow policy.

    The `callback` policy is special, in that it will retry
    the failed composition after the callback has been
    called. This is to allow callbacks to grow a composer as
    needed. If the retry fails, the function exits.

    Params:
        args = The components of the message to join
    */
    ref Composer write(A...)(A args)
    {
        static import composer.writer;

        clear();

        auto buffer = composer.writer.Buffer!Char(_buffer);
        const result = composer.writer.write(buffer, args);
        
        if (result.numCharsWritten > 0)
        {
            _nextCharIndex = result.numCharsWritten;
        }
        else
        {
            static if (policy == OverflowPolicy.callback)
                _overflowCallback(this);
            else static if (policy == OverflowPolicy.exception)
                throw new Exception("Composer buffer at capacity");
            else static if (policy == OverflowPolicy.assertFalse)
                assert(false, "Composer buffer at capacity");
        }

        return this;
    }

private:
    static if (buffSize == runtime)
        Char[] _buffer;
    else
        Char[buffSize] _buffer;
    
    ///The index of the next available character
    size_t _nextCharIndex;

    static if (policy == OverflowPolicy.callback)
        OverflowCallback _overflowCallback;
}

@("Composer.dynamic.write")
@safe @nogc pure nothrow unittest
{
    char[1024] msgBuffer;

    auto composer = Composer!char(msgBuffer);

    auto ptr = () @trusted { return cast(void*) 0xDEADBEEF; } ();
    auto cmp = composer.write("This is a message with numbers: ", 12, ", and pointers: ", ptr);

    assert(cmp.message == "This is a message with numbers: 12, and pointers: void*(0xDEADBEEF)");
}

@("Composer.static.write")
@safe @nogc pure nothrow unittest
{
    auto composer = Composer!(char, 2014)();

    auto ptr = () @trusted { return cast(uint*) 0xDEADBEEF; } ();
    auto cmp = composer.write("This is a message with numbers: ", 12, ", and pointers: ", ptr);

    assert(cmp.message == "This is a message with numbers: 12, and pointers: uint*(0xDEADBEEF)");
}
