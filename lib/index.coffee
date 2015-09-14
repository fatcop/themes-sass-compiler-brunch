sysPath = require('path')
util = require('util')
libsass = require('node-sass')
fs =  require('fs')
colors = require('colors')
mkdirp = require('mkdirp')
anymatch = require('anymatch')

sassRe = /\.[sc][ac]?ss$/

extend = (object, source) ->
  for key of source
    object[key] = source[key]
  object

class ThemesSASSCompiler
  brunchPlugin: yes
  type: 'stylesheet'
  pattern: sassRe

  constructor: (@cfg) ->
    @joinTo = @cfg.files.stylesheets.joinTo if @cfg.files and @cfg.files.stylesheets and @cfg.files.stylesheets.joinTo
    @rootPath = @cfg.paths.root;
    @optimize = @cfg.optimize
    @config = (@cfg.plugins && @cfg.plugins.themes_sass) || {};
    @baseDir = if @config.options and @config.options.baseDir then @config.options.baseDir else 'base'
    @sassDir = if @config.options and @config.options.sassDir then @config.options.sassDir else 'sass'
    @absAppDir = sysPath.resolve('app')
    @baseSassDir = sysPath.join('app', @baseDir, @sassDir)
    @outputPath = sysPath.resolve @cfg.paths.public
    if @config.options and @config.options.includePaths
      @includePaths = @config.options.includePaths
    @outStyle = if @cfg.optimize then 'compressed' else 'nested'
    @themeDirs = @_getDirectories @absAppDir
    @themeSassFiles = {}

    @themeDirs.forEach (name) =>
      themeSassDir = sysPath.join @absAppDir, name , @sassDir
      files = @_findFilesInDir(themeSassDir, name , sassRe)
      @themeSassFiles[name] = files

#    console.log @themeSassFiles

  _findFilesInDir: (startPath, theme, filter) =>
    results = {}
    if !fs.existsSync(startPath)
      return
    files = fs.readdirSync(startPath)
    i = 0
    while i < files.length
      filename = sysPath.join(startPath, files[i])
      stat = fs.lstatSync(filename)
      if stat.isDirectory()
        results = extend(results, @_findFilesInDir(filename, theme, filter))
      else if anymatch(filter, filename)
        importPath = filename.replace('_', '').replace(sassRe,'')
        results[importPath] = filename
      i++
    results

  _getDirectories: (path) ->
    fs.readdirSync(path).filter (file) ->
      fs.statSync(sysPath.join(path, file)).isDirectory()

  _getIncludePaths: (path) =>
    includePaths = [
      @rootPath
      sysPath.dirname(path)
    ]
    if Array.isArray(@includePaths)
      includePaths = includePaths.concat(@includePaths)
    includePaths

  _urlImporter: (url, prev, theme)=>
    #Convert import urls to absolute paths and match against theme for substitution
    sassDir = sysPath.join(@absAppDir, theme, @sassDir)
    getAbsImport = (imp_url, prev_url) =>
      if prev_url != "stdin"
        import_url = sysPath.dirname(sysPath.join(sassDir, prev_url.replace(@baseSassDir, '')))
        import_url = sysPath.join(import_url,imp_url)
      else
        import_url = sysPath.join(sassDir, imp_url.replace(@baseSassDir, ''))
      match_file = @themeSassFiles[theme].hasOwnProperty(import_url)
      if match_file
        import_url = @themeSassFiles[theme][import_url]
      else
        import_url = imp_url
      import_url
    if theme != @baseDir
      url = getAbsImport(url, prev)
    return { file: url }

  _nativeCompile: (source, themeDirs, callback)=>
    theme = themeDirs.pop()
    outputPath = source.outputPath.replace new RegExp(@baseDir), theme
    libsass.render {
      data: source.data
      includePaths: @_getIncludePaths(source.path)
      outputStyle: @outStyle
      indentedSyntax: (sysPath.extname(source.path) == '.sass')
      sourceComments: !@optimize
      sourceMap: true
      outFile: outputPath
      importer: (url, prev, done)=>
          result = @_urlImporter(url, prev, theme)
          return { file: result.file }
    }, (error, result) =>
      if error
        callback error.message || util.inspect(error)
      else
        if result.css
          data = result.css.toString()
          mkdirp sysPath.dirname(outputPath), (err)=>
            if err
              console.log err.red
            else
              fs.writeFile outputPath, data, (err)=>
                if err
                  console.log err.red
                else
                  #Output successful file creation to console.
                  msg = 'Wrote: '.green + theme.toUpperCase().underline + ' ' +
                        sysPath.basename(outputPath).bold +
                        ' -> '.reset + sysPath.dirname(outputPath)
                  console.log(msg)

                  #Create the .map files for each css file if map data exists.
                  if result.map
                    map = result.map.toString()
                    fs.writeFile outputPath.concat('.map'), map, (err)=>
                      if err
                        console.log error.red

                  #Recursively go through each theme dir and compile until they are all done.
                  #If file written for each theme fire final callback to brunch to signal completion of compile
                  if themeDirs.length
                    @_nativeCompile(source, themeDirs, callback)
                  else
                    callback null, null


  compile: (data, path, callback) =>
    if !data.trim().length
      return callback(null, '')
    outputPath = @outputPath
    for outPath, inPath of @joinTo
        outputPath = sysPath.join(@outputPath, outPath) if anymatch(inPath, path)
    dirs = @_getDirectories @absAppDir
    source =
      data: data
      path: path
      outputPath: outputPath
    @_nativeCompile source, dirs, callback

    return

module.exports = ThemesSASSCompiler