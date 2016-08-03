import strutils, sequtils, endians
include bin_utils

#-----------------
proc rol*(x: uint8, y: uint8): uint8 =
    result = (x shl (y and 7'u8)) or (x shr (8'u8 - (y and 7'u8)))

proc rol*(x: uint16, y: uint8): uint16 =
    result = (x shl (y and 15'u8)) or (x shr (16'u8 - (y and 15'u8)))

proc rol*(x: uint32, y: uint8): uint32 =
    result = (x shl (y and 31'u8)) or (x shr (32'u8 - (y and 31'u8)))

proc rol*(x: uint64, y: uint8): uint64 =
    ## rotates left with wrap-around any unsigned integer
    result = (x shl (y and 63'u8)) or (x shr (64'u8 - (y and 63'u8)))

#-----------------
proc ror*(x: uint8, y: uint8): uint8 =
    result = (x shr (y and 7'u8)) or (x shl (8'u8 - (y and 7'u8)))

proc ror*(x: uint16, y: uint8): uint16 =
    result = (x shr (y and 15'u8)) or (x shl (16'u8 - (y and 15'u8)))

proc ror*(x: uint32, y: uint8): uint32 =
    result = (x shr (y and 31'u8)) or (x shl (32'u8 - (y and 31'u8)))

proc ror*(x: uint64, y: uint8): uint64 =
    ## rotates right with wrap-around any unsigned integer
    result = (x shr (y and 63'u8)) or (x shl (64'u8 - (y and 63'u8)))
#-----------------


type
    binBufferObj = object
        data: cstring
        size: int
        view: Slice[int]
    binBuffer* = ref binBufferObj


proc len*(buff: binBuffer): int =
    result = buff.view.b - buff.view.a + 1


proc toBinBuffer*[T](data: openArray[T]): binBuffer = 
    new(result)
    result.data = cast[cstring](unsafeAddr data[0])
    result.size = data.len * T.sizeof
    result.view = 0 .. <result.size


proc `[]`*(buff: binBuffer, n: int): var byte =
    if n > <buff.len:
        raise newException(IndexError, "Invalid index: " & $n)

    result = cast[ptr byte](addr buff.data[buff.view.a + n])[]


proc `[]=`*(buff: binBuffer, n: int, val: byte) =
    if n  > <buff.len:
        raise newException(IndexError, "Invalid index: " & $n)

    cast[ptr byte](addr buff.data[buff.view.a + n])[] = val


proc `[]`*(buff: binBuffer, s: Slice[int]): binBuffer = 
    ## Slices `buff` to (and including) the desired limits. The underlying data array 
    ## is shared across slices. The 's' limits are limited to the
    ## original data size so is possible to grow back a slice up to
    ## the maximum size. 
    new(result)
    shallowCopy(result[], buff[])
    
    # allow expanding to original size
    result.view.b = (buff.view.a + s.b).clamp(0, <buff.size)
    result.view.a = (buff.view.a + s.a).clamp(0, <buff.size)

    if result.view.a > result.view.b:
        swap (result.view.a, result.view.b)

iterator items*(buff: binBuffer): byte =
  for n in buff.view:
    yield buff[n]

iterator mitems*(buff: binBuffer): var byte =
  for n in buff.view:
    yield buff[n]

iterator citems*(data: openArray[byte]): byte {.closure.} = 
    var
        n = data.len
        i = 0

    while true:
        yield data[i]
        if i == <n: i = 0 else: inc(i)

iterator citems1*(data: binBuffer): byte {.closure.} = 
    var
        n = data.len
        i = 0

    while true:
        yield data[i]
        if i == <n: i = 0 else: inc(i)


# need several variants. How to merge into generics without any system.xor conflict?
proc `xor`*[T](buff: seq[T], mask: openArray[T]): seq[T] = 
    var c = citems
    result = buff.mapIt(it xor c(mask))

proc `xor`*[T](buff: binBuffer, mask: openArray[T]): seq[T] = 
    var c = citems
    result = buff.mapIt(it xor c(mask))

proc `xor`*(buff: binBuffer, mask: binBuffer): seq[byte] = 
    var c = citems1
    result = buff.mapIt(it xor c(mask))

proc `xor`*[T](buff: seq[T], mask: binBuffer): seq[T] =
    var c = citems1
    result = buff.mapIt(it xor c(mask))


proc copy*(dst: binBuffer; src: binBuffer) = 
    var n = (src.len).clamp(0, dst.len)
    copyMem(addr dst.data[dst.view.a], addr src.data[src.view.a], n)


#-----------------------
proc loadHigh*[T: SomeUnsignedInt](buff: binBuffer, value: var T, offset: int = 0): bool =
    ##  Reads an unsigned integer of type T from a sequence of bytes representing a big endian number.
    ## - value = var type pointer to the mutable integer (holder for the read value)
    ## - data = the byte array where to read from
    ## - offset = the element in the data array where to start. Defaults to zero if missing.
    ## Note: the routine will test if the offset position allows for the full T value to be read
    ## (i.e. there are enough bytes left to complete T size)

    var n = buff.view.a + offset  

    if (buff.view.b + 1 ) >= (n + sizeof(value)):
        result = true

        var i: pointer = addr buff.data[n]
        var o: pointer = addr value

        case sizeof(value)
        of 1:
            value = ord(buff.data[0])
        of 2:
            bigEndian16(o, i)
        of 4:
            bigEndian32(o, i)
        of 8:
            bigEndian64(o, i)
        else:
            result = false
    else:
        result = false
        assert(false, "Invalid load offset: " & $n & " in " & $buff.view)


proc storeHigh*[T: SomeUnsignedInt](buff: binBuffer, value: T, offset: int = 0): bool =
  
    var n = buff.view.a + offset  

    if (buff.view.b + 1 ) >= (n + sizeof(value)):
        result = true

        var o: pointer = addr buff.data[buff.view.a + offset]
        var i: pointer = unsafeAddr value
        
        case sizeof(value)
        of 1:
          buff.data[0] = char(value.byte)
        of 2:
          bigEndian16(o, i)
        of 4:
          bigEndian32(o, i)
        of 8:
          bigEndian64(o, i)
        else:
          result = false
    else:
      result = false
      assert(false, "Invalid store offset: " & $n & " in " & $buff.view)
