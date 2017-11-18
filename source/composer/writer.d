module composer.writer;

import std.traits: isSomeChar, isSomeString, isArray, isIntegral, isPointer;

version(unittest) import unit_threaded;
else enum ShouldFail;

struct Buffer(Char) {
    Char[] buffer;
    alias buffer this;

    size_t numCharsWritten;
}

/**
Writes a value to the buffer.

Supported types:
    * bool
    * char
    * string
    * byte/short/int/long and their unsigned counterparts
    * structs (todo)
    * classes (todo)
    * arrays
    * floating-point values (todo)
    * pointers (in hexadecimal)

Params:
    buffer = The buffer to write to
    value  = The value to write to the buffer

Returns:
    The remainder of the buffer that has not been written to
    yet, and the number of characters that were written by
    the function. In the event of error, `numCharsWritten`
    will be 0.
*/
auto write(Char, A...)(auto ref Buffer!Char buffer, A args)
{
    auto activeBuffer = buffer;

    foreach(ref arg; args)
    {
        activeBuffer = activeBuffer.write(arg);

        if (activeBuffer.numCharsWritten == 0)
            return result(buffer, 0);
    }

    return activeBuffer;
}

@("write.all")
@safe @nogc pure nothrow unittest
{
    char[128] chars;
    auto result = write(Buffer!char(chars[]), "testMSG ", 20, 'c', " alo ", false);

    assert(chars[0 .. result.numCharsWritten] == "testMSG 20c alo false");
}

///ditto
@safe @nogc
auto write(Char, T)(ref Buffer!Char buffer, T integral)
    if (isSomeChar!Char && isIntegral!T && !is(T == enum))
{
    import std.traits: Unqual, Unsigned;

    enum charBufferLength = 32;
    Char[charBufferLength] buf = void;
    size_t charIndex = charBufferLength - 1;

    const negative = integral < 0;
    Unqual!(Unsigned!T) value = negative ? -integral : integral;

    while (value >= 10)
    {
        buf[charIndex] = cast(Char) ((value % 10) + '0');
        value /= 10;
        charIndex--;
    }

    buf[charIndex] = cast(char) (value + '0');

    if (negative)
    {
        charIndex--;
        buf[charIndex] = '-';
    }

    const strLength = charBufferLength - charIndex;
    buffer[0 .. strLength] = buf[charIndex .. $];

    return result(buffer, strLength);
}

///ditto
@safe @nogc
auto write(Char, T)(ref Buffer!Char buffer, T boolValue)
    if (isSomeChar!Char && is(T == bool))
{
    import std.utf: byUTF;
    import std.array: array;

    static immutable strings = ["false".byUTF!Char.array, "true".byUTF!Char.array];

    const stringLength = strings[boolValue].length;
    if (buffer.length >= stringLength)
        buffer[0 .. stringLength] = strings[boolValue];

    return result(buffer, stringLength);
}

@("write.bool")
@safe @nogc pure nothrow unittest
{
    char[32] chars;
    auto result = Buffer!char(chars[]).write(true);
    assert(chars[0..result.numCharsWritten] == "true");

    result = Buffer!char(chars[]).write(false);
    assert(chars[0..result.numCharsWritten] == "false");
}

///ditto
@safe @nogc
auto write(Char, T)(ref Buffer!Char buffer, T character)
    if (isSomeChar!Char && isSomeChar!T)
{
    import std.utf: byUTF, codeLength;

    const numRequiredChars = character.codeLength!Char;
    if (numRequiredChars > buffer.length)
        return result(buffer, 0);
    
    T[1] slice = [character];

    size_t index;
    foreach(c; slice[].byUTF!Char)
    {
        buffer[index] = c;
        index++;
    }

    assert(index == numRequiredChars);

    return result(buffer, numRequiredChars);
}

///ditto
@safe @nogc
auto write(Char, T)(ref Buffer!Char buffer, T pointer)
    if (isSomeChar!Char && isPointer!T)
{
    import std.traits: PointerTarget, fullyQualifiedName;
    import std.conv: toChars, LetterCase;

    //to allow for @nogc annotation
    static immutable string tName = fullyQualifiedName!T;
    
    auto activeBuffer = buffer.write(tName, '(');
    const value = cast(size_t) pointer;

    if (pointer is null)
        activeBuffer = activeBuffer.write("null");
    else
    {//write address as hexadecimal
        activeBuffer = activeBuffer.write("0x");
        foreach(hexChar; value.toChars!(16, Char, LetterCase.upper))
        {
            activeBuffer = activeBuffer.write(hexChar);

            if (activeBuffer.numCharsWritten == 0)
                return result(buffer, 0);
        }
    }

    activeBuffer = activeBuffer.write(')');

    if (activeBuffer.numCharsWritten == 0)
        return result(buffer, 0);

    return activeBuffer;
}

@("write.pointer")
@safe @nogc pure nothrow
unittest
{
    char[32] chars;
    auto buffer = Buffer!char(chars[]);
    auto result = buffer.write(()@trusted{return cast(char*) 0xDEADBEEF;}());
    auto resultStr = chars[0..result.numCharsWritten];

    assert(resultStr == "char*(0xDEADBEEF)");
}

///ditto
auto write(Char, T)(ref Buffer!Char buffer, T array)
    if (isSomeChar!Char && isArray!T && !isSomeString!T)
{
    import std.traits: fullyQualifiedName;
    auto activeBuffer = buffer.write(fullyQualifiedName!T);

    //take of the trailing `]` character
    activeBuffer.buffer = buffer[fullyQualifiedName!T.length - 1 .. $];
    activeBuffer.numCharsWritten -= 1;

    // if the array is not empty, print contents in comma-separated list
    if (array.length > 0)
    {
        activeBuffer = activeBuffer.write(array[0]);

        foreach(value; array[1 .. $])
        {
            activeBuffer = activeBuffer.write(", ", value);

            if (activeBuffer.numCharsWritten == 0)
                return result(buffer, 0);
        }
    }

    activeBuffer = activeBuffer.write(']');

    if (activeBuffer.numCharsWritten == 0)
        return result(buffer, 0);

    return activeBuffer;
}

@("write.array")
@safe pure nothrow unittest
{
    static immutable array = [0, 1, -2, 3, 400];

    char[32] chars;
    auto buffer = Buffer!char(chars[]);
    auto result = buffer.write(array);
    const str = chars[0 .. result.numCharsWritten];
    assert(chars[0 .. result.numCharsWritten] == "immutable(int)[0, 1, -2, 3, 400]");
}

///ditto
@safe @nogc
auto write(Char, T)(ref Buffer!Char buffer, T str)
    if (isSomeChar!Char && isSomeString!T)
{
    import std.range: ElementEncodingType;

    static if (is(ElementEncodingType!T == Char))
    {
        import core.stdc.string: memcpy;

        if (str.length > buffer.length)
            return result(buffer, 0);

        memcpy(&buffer[0], &str[0], str.length * Char.sizeof);

        return result(buffer, str.length);
    }
    else
    {
        import std.utf: byUTF;

        size_t numCharsWritten;

        foreach(strChar; str.byUTF!Char)
        {
            assert(numCharsWritten < buffer.length);
            buffer[numCharsWritten] = strChar;
            numCharsWritten++;

            if (numCharsWritten >= buffer.length)
                return result(buffer, 0);
        }

        return result(buffer, numCharsWritten);
    }
}

version(unittest)
@Types!(char, wchar, dchar)
@safe writeString(T)() {
    import std.utf: byUTF;
    import std.array: array;

    static immutable testString = "this is a string".byUTF!T.array;

    @safe void testWrite(Char)()
    {
        Char[32] chars;
        auto buffer = Buffer!Char(chars[]);
        auto result = buffer.write(testString);

        result.numCharsWritten.shouldEqual(testString.length);
        result.buffer.length.shouldEqual(chars.length - testString.length);
        chars[0..result.numCharsWritten].shouldEqual(testString);
    }

    testWrite!char;
    testWrite!wchar;
    testWrite!dchar;
}

///ditto
auto write(Char, T)(ref Buffer!Char buffer, T object)
    if (isSomeChar!Char && (is(T == class) || is(T == interface)))
{
    import std.traits: hasMember, fullyQualifiedName;

    if (object is null)
        return buffer.write("null");
    
    static if (hasMember!(T, "toString"))
        return buffer.write(object.toString());
    else
        return buffer.dumpObjectContents(structure);
}

///ditto
auto write(Char, T)(ref Buffer!Char buffer, auto ref T structure)
    if (isSomeChar!Char && is(T == struct))
{
    import std.traits: hasMember;

    static if (hasMember!(T, "toString"))
        return buffer.write(structure.toString());
    else
        return buffer.dumpObjectContents(structure);
}

@("write.struct")
@safe @nogc pure nothrow unittest
{
    struct TestStruct
    {
        int value;
        bool flag;
        string msg;
    }

    char[128] chars;
    auto buffer = Buffer!char(chars[]);
    auto result = buffer.write(TestStruct(-129873, false, "Hello!"));
    auto resultStr = chars[0..result.numCharsWritten];
    // writelnUt(resultStr);
}

@safe @nogc dumpObjectContents(Char, T)(ref Buffer!Char buffer, auto ref T object) pure nothrow
{
    import std.traits: FieldNameTuple, fullyQualifiedName;

    auto activeBuffer = buffer;

    activeBuffer = activeBuffer.write(fullyQualifiedName!T, "{ ");

    if (activeBuffer.numCharsWritten == 0)
        return result(buffer, 0);

    enum fields = FieldNameTuple!T;
    
    if (fields.length > 0)
    {
        mixin("activeBuffer = activeBuffer.write(fields[0], \": \", object." ~ fields[0] ~ ");");
        
        if (activeBuffer.numCharsWritten == 0)
            return result(buffer, 0);
    }

    static foreach(field; fields)
    {
        activeBuffer = activeBuffer.write(", ");
        mixin("activeBuffer = activeBuffer.write(field, \": \", object." ~ field ~ ");");

        if (activeBuffer.numCharsWritten == 0)
            return result(buffer, 0);
    }

    activeBuffer = activeBuffer.write(" }");

    return activeBuffer;
}

pragma(inline)
private auto result(Char)(ref Buffer!Char buffer, size_t numCharsWritten)
{
    return Buffer!Char(buffer[numCharsWritten .. $], buffer.numCharsWritten + numCharsWritten);
}
