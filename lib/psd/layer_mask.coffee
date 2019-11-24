_ = require 'lodash'
iconv = require 'iconv-lite'
Util = require './util.coffee'
Layer = require './layer.coffee'

# The layer mask is the overarching data structure that describes both
# the layers/groups in the PSD document, and the global mask.
# This part of the document is ordered as such:
#
# * Layers
# * Layer images
# * Global Mask
#
# The file does not need to have a global mask. If there is none, then
# its length will be zero.
module.exports = class LayerMask
  constructor: (@file, @header) ->
    @layers = []
    @mergedAlpha = false
    @globalMask = null
    @patterns = []
    @textInfo = []

  skip: -> @file.seek @file.readInt(), true

  parse: ->
    maskSize = @file.readInt()
    start_position = @file.tell()
    finish = start_position + maskSize

    return if maskSize <= 0

    if @bitDepth == 16
      @file.read(16)

    @parseGlobalMask()
    @parseLayers()

    consumed_bytes = @file.tell() - start_position
    parse_layer_tagged_blocks(mask_size - consumed_bytes)

    # Ensure we're at the end of this section
    @file.seek finish

    # The layers are stored in the reverse order that we would like them. In other
    # words, they're stored bottom to top and we want them top to bottom.
    @layers.reverse()

    while @file.pos < finish and !@file.data[@file.pos]
      @file.seek 1, true

    while @file.pos < finish and @file.readString(4) == '8BIM'
      str = @file.readString(4)
      sectionLen = @file.readInt()
      endSection = ((sectionLen + 3) & ~3) + @file.tell()
      if sectionLen > 0
        @file.seek -4, true
        switch str
          when 'Patt', 'Pat2', 'Pat3' then @parsePatterns()
        @file.seek endSection

    @file.seek finish

  parse_layer_tagged_blocks: (remaining_length) ->
    start_pos = @file.tell()
    read_bytes = 0

    while read_bytes < remaining_length
        res = parse_additional_layer_info_block
        read_bytes = @file.tell() - start_pos

    parse_additional_layer_info_block: ->
      sig = @file.readString(4)

      if sig != '8BIM' or sig != '8B64'
        @file.seek -4, true
        return false

      key = @file.readString(4)

      if key == 'Lr16' or key == 'Lr32'
        parseLayers()
        return true

  parseLayers: ->
    layerInfoSize = Util.pad2 @file.readInt()

    if layerInfoSize is 0 and (@header.depth is 16 or @header.depth is 32)
        @file.pos = @file.pos + 12
        layerInfoSize = Util.pad2 @file.readInt()

    if layerInfoSize > 0
      layerCount = @file.readShort()

      if layerCount < 0
        layerCount = Math.abs layerCount
        @mergedAlpha = true

      for i in [0...layerCount]
        @layers.push new Layer(@file, @header).parse()

      layer.parseChannelImage() for layer in @layers

  parseGlobalMask: ->
    length = @file.readInt()
    return if length <= 0

    maskEnd = @file.tell() + length + 3

    @globalMask = _({}).tap (mask) =>
      mask.overlayColorSpace = @file.readShort()
      mask.colorComponents = [
        @file.readShort() >> 8
        @file.readShort() >> 8
        @file.readShort() >> 8
        @file.readShort() >> 8
      ]

      mask.opacity = @file.readShort() / 16.0

      # 0 = color selected, 1 = color protected, 128 = use value per layer
      mask.kind = @file.readByte()

    @file.seek maskEnd

  getPatternAsPNG: (pattern) ->
    canvas = document.createElement('canvas')
    canvas.width = pattern.width
    canvas.height = pattern.height
    ctx = canvas.getContext('2d')
    imageData = ctx.createImageData(pattern.width, pattern.height)
    pixelData = imageData.data
    numPixels = pattern.width * pattern.height
    nbChannels = pattern.data.slice(0,24).length
    for i in [0...numPixels]
      r = g = b = 0
      a = 255

      for chan in [0...nbChannels]
        channelData = pattern.data[chan]
        val = channelData[i]

        switch chan
          when 0 then  r = val
          when 1 then  g = val
          when 2 then  b = val
          when 3 then a = val
      pixelData.set([r, g, b, a], i*4)

      if pattern.data[24]
        channelData = pattern.data[24]
        for i in [0...numPixels]
          val = channelData[i]
          pixelData[i*4 + 3] = val
    ctx.putImageData(imageData, 0, 0)
    canvas.toDataURL("image/png")

  parsePatterns: ->
    file = @file
    patterns = @patterns
    getPatternAsPNG = @getPatternAsPNG
    readVirtualMemoryArrayList = ->
      file.seek 4, true # version
      VMALEnd = file.readInt() + file.tell()
      pattern = {top: file.readInt(), left: file.readInt(), bottom: file.readInt(), right : file.readInt(), channels: file.readInt(), data: []}
      pattern.width = pattern.right - pattern.left
      pattern.height = pattern.bottom - pattern.top
      pattern.toURL = () ->
        getPatternAsPNG(@)
      for i in [0...pattern.channels+2]
        lineIndex = 0
        chanPos = 0
        if !file.readInt()
          continue
        l = file.readInt()
        endChannel =  l + file.tell()
        depth = file.readInt()
        file.readInt()
        file.readInt()
        file.readInt()
        file.readInt()
        file.readShort()
        compressed = file.readByte()
        if compressed
          byteCounts = []
          pattern.data[i] = new Uint8Array(pattern.width*pattern.height)
          for j in [0...pattern.height]
            byteCounts.push(file.readShort());
          for j in [0...pattern.height]
            finish = file.tell() + byteCounts[lineIndex + j]
            while file.tell() < finish
              len = file.read(1)[0]
              if len < 128
                len += 1
                data = file.read(len)
                pattern.data[i].set data, chanPos
                chanPos += len
              else if len > 128
                len ^= 0xff
                len += 2
                val = file.read(1)[0]
                pattern.data[i].fill(val, chanPos, chanPos+len)
                chanPos += len
          lineIndex += pattern.height
        else
          pattern.data[i] = new Uint8Array(file.read(l-23))
        file.seek endChannel
      file.seek VMALEnd
      pattern

    readPattern = ->
      patternEnd = ((file.readInt() + 3) & ~3) + file.tell()
      file.seek 4, true # version
      mode = file.readInt()
      point = [file.readShort(), file.readShort()]
      pattern = {name: file.readUnicodeString(), id: file.readString(file.readByte()), palette: []}
      if mode == 2
        pattern.palette = file.read(256*3)
      pattern.data = readVirtualMemoryArrayList()
      patterns.push(pattern)
      file.seek patternEnd

    patternsEnd = file.readInt() + file.tell()
    readPattern() while file.tell() < patternsEnd
