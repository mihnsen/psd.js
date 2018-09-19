var PSD, fixturesPath, fs, outputPath, path, rimraf, should

PSD = require('../lib/psd.js')

fs = require('fs')

rimraf = require('rimraf')

path = require('path')

should = require('should')

outputPath = path.resolve(__dirname, 'output')

fixturesPath = path.resolve(__dirname, 'fixtures')

describe('exporting from a PSD', function() {
  beforeEach(function(done) {
    return fs.mkdir(outputPath, done)
  })
  afterEach(function(done) {
    return rimraf(outputPath, done)
  })
  it('should export a png', function(done) {
    var expectedPath, filePath, psdPath
    psdPath = path.resolve(__dirname, '../', 'examples/images/example.psd')
    filePath = path.join(outputPath, 'out.png')
    expectedPath = path.join(fixturesPath, 'out.png')
    return PSD.open(psdPath)
      .then(function(psd) {
        return psd.image.saveAsPng(filePath)
      })
      .then(function() {
        return fs
          .statSync(filePath)
          .size.should.eql(fs.statSync(expectedPath).size)
      })
      .then(function() {
        return done()
      })
      ['catch'](done)
  })
  return it('should export correct position and size', function(done) {
    var filePath
    filePath = path.join(fixturesPath, '(size)45-keyShapeInvalidated.psd')
    return PSD.open(filePath)
      .then(function(psd) {
        var node, tree
        psd.parse()
        tree = psd.tree()
        fs.writeFileSync(
          './export.json',
          JSON.stringify(tree['export'](), null, 2)
        )
        node = tree.get('矩形 28 副本 13 拷贝 2')
        return console.log(node)
      })
      .then(function() {
        return done()
      })
      ['catch'](done)
  })
})
