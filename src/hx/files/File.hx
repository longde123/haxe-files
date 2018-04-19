/*
 * Copyright (c) 2016-2018 Vegard IT GmbH, https://vegardit.com
 * SPDX-License-Identifier: Apache-2.0
 */
package hx.files;

import hx.concurrent.ConcurrentException;
import hx.strings.internal.Either2;

#if (sys || macro)
import sys.io.FileInput;
import sys.io.FileOutput;
#end

#if (sys || macro || nodejs)
import sys.FileStat;
import sys.FileSystem;
#end

using hx.strings.Strings;

/**
 * Represents a regular file.
 *
 * @author Sebastian Thomschke, Vegard IT GmbH
 */
class File {

    /**
     * This method does not check if the path actually exists and if it currently points to a directory or a file
     *
     * @param trimWhiteSpaces controls if leading/trailing whitespaces of path elements shall be removed automatically
     */
    public static function of(path:Either2<String, Path>, trimWhiteSpaces = true):File {
        if (path == null)
            return new File(Path.of(null));

        return switch(path.value) {
            case a(str): new File(Path.of(str, trimWhiteSpaces));
            case b(obj): new File(obj);
        }
    }


    public var path(default, null):Path;


    inline
    function new(path:Path) {
        this.path = path;
    }


    function assertValidPath(mustExist = true) {
        if (path.filename.isEmpty())
            throw "[path.filename] must not be null or empty!";

        if (path.exists()) {
            if (!path.isFile()) throw '[path] "$path" exists but is not a file!';
        } else {
            if (mustExist) throw '[path] "$path" does not exist!';
        }
    }


    #if (sys || macro)
    function openInput(binary = true):FileInput {
        return sys.io.File.read(toString(), binary);
    }


    function openOutput(mode:FileWriteMode, binary = true):FileOutput {
        return switch(mode) {
            case REPLACE: sys.io.File.write(toString(), binary);
            #if (haxe_ver >= 4.0)
            case UPDATE:  sys.io.File.update(toString(), binary);
            #end
            case APPEND:  sys.io.File.append(toString(), binary);
        }
    }
    #end


    /**
     * <pre><code>
     * >>> File.of("target/test.txt").writeString("HEY!", true)           throws nothing
     * >>> File.of("target/test.txt").appendString("HO!")                 throws nothing
     * >>> File.of("target/test.txt").readAsString().indexOf("HEY!") > -1 == true
     * >>> File.of("target/test.txt").delete()                            == true
     * >>> File.of(""               ).appendString("")                    throws "[path.filename] must not be null or empty!"
     * </code></pre>
     */
    public function appendString(content:String):Void {

        assertValidPath(false);

        if (content == null)
            return;

        #if (sys || macro)
            var ex:ConcurrentException = null;
            var out = sys.io.File.append(path.toString());
            try {
                out.writeString(content);
            } catch (e:Dynamic) {
                ex = ConcurrentException.capture(e);
            }
            out.close();
            if (ex != null)
                ex.rethrow();
        #elseif nodejs
            js.node.Fs.appendFileSync(path.toString(), content);
        #elseif phantomjs
            js.phantomjs.FileSystem.write(path.toString(), content, "a");
        #else
            throw "Operation not supported on current target.";
        #end
    }


    /**
     * Delete the file.
     *
     * <pre><code>
     * >>> File.of("target/test.txt").writeString("HEY!", true) throws nothing
     * >>> File.of("target/test.txt").delete() == true
     * >>> File.of("target"         ).delete() throws '[path] "target" exists but is not a file!'
     * >>> File.of(""               ).delete() == false
     * >>> File.of(null             ).delete() == false
     * <code></pre>
     *
     * @return false if path does not exist
     *
     * @throws if path is not a file
     */
    public function delete():Bool {

        if (!path.exists())
            return false;

        assertValidPath();

        #if (sys || macro || nodejs)
            FileSystem.deleteFile(path.toString());
            return true;
        #elseif phantomjs
            js.phantomjs.FileSystem.remove(path.toString());
            return true;
        #else
            throw "Operation not supported on current target.";
        #end
    }


    /**
     * <pre><code>
     * >>> File.of("CHANGELOG.md").readAsBytes().length > 0
     * >>> File.of("nonexistent" ).readAsBytes() == null
     * >>> File.of(""            ).readAsBytes() == null
     * >>> File.of(null          ).readAsBytes() == null
     * >>> File.of("."           ).readAsBytes() throws '[path] "." exists but is not a file!'
     * >>> File.of("src"         ).readAsBytes() throws '[path] "src" exists but is not a file!'
     * </code></pre>
     *
     * @return null in case the file does not exist
     *
     * @throws if path is not a file
     */
    public function readAsBytes():haxe.io.Bytes {
        if (!path.exists())
            return null;

        assertValidPath();

        #if (sys || macro || nodejs)
            return sys.io.File.getBytes(path.toString());
        #elseif phantomjs
            return haxe.io.Bytes.ofString(js.phantomjs.FileSystem.read(path.toString()));
        #else
            throw "Operation not supported on current target.";
        #end
    }


    /**
     * <pre><code>
     * >>> File.of("CHANGELOG.md").readAsString().indexOf("Initial release") > -1 == true
     * >>> File.of("nonexistent" ).readAsString() == null
     * >>> File.of(""            ).readAsString() == null
     * >>> File.of(null          ).readAsString() == null
     * >>> File.of("."           ).readAsString() throws '[path] "." exists but is not a file!'
     * >>> File.of("src"         ).readAsString() throws '[path] "src" exists but is not a file!'
     * </code></pre>
     *
     * @param defaultValue string to be returned in case the file does not exist
     *
     * @throws if path is not a file
     */
    public function readAsString(?defaultValue:String = null):String {
        if (!path.exists())
            return defaultValue;

        assertValidPath();

        #if (sys || macro || nodejs)
            return sys.io.File.getContent(path.toString());
        #elseif phantomjs
            return js.phantomjs.FileSystem.read(path.toString());
        #else
            throw "Operation not supported on current target.";
        #end
    }


    /**
     * Copies the given file.
     *
     * <pre><code>
     * >>> File.of("target/foo.txt").writeString("HEY!") throws nothing
     * >>> File.of("target/foo.txt").copyTo("target/bar.txt") throws nothing
     * >>> File.of("target/foo.txt").copyTo("target/bar.txt") throws '[newPath] "target' + Path.of("").dirSep + 'bar.txt" already exists!'
     * >>> File.of("target/foo.txt").path.exists()            == true
     * >>> File.of("target/bar.txt").path.exists()            == true
     * >>> File.of("target/foo.txt").delete()                 == true
     * >>> File.of("target/bar.txt").delete()                 == true
     *
     * >>> File.of("README.md"  ).copyTo("") throws "[newPath] must not be null or empty!"
     * >>> File.of("nonexistent").copyTo("") throws '[path] "nonexistent" does not exist!'
     * >>> File.of(""           ).copyTo("") throws "[path.filename] must not be null or empty!"
     * </code></pre>
     *
     * @param overwrite if set to true any file already existing at newPath will be deleted automatically
     * @param trimWhiteSpaces controls if leading/trailing whitespaces of path elements shall be removed automatically
     */
    public function copyTo(newPath:Either2<String, Path>, overwrite = false, trimWhiteSpaces = true):File {
        assertValidPath();

        if (newPath == null)
            throw "[newPath] must not be null or empty!";

        var targetPath:Path = switch(newPath.value) {
            case a(str): Path.of(str, trimWhiteSpaces);
            case b(obj): obj;
        }

        if (targetPath.filename == "")
            throw "[newPath] must not be null or empty!";

        if (path.getAbsolutePath() == targetPath.getAbsolutePath())
            return this;

        var targetFile = targetPath.toFile();

        if (targetPath.exists()) {
            if (!overwrite)
                throw '[newPath] "$targetPath" already exists!';

            if (!targetPath.isFile())
                throw '[newPath] "$targetPath" already exists and is not a file!';

            targetFile.delete();
        }

        #if (sys || macro || nodejs)
            sys.io.File.copy(path.toString(), targetPath.toString());
        #elseif phantomjs
            js.phantomjs.FileSystem.copy(path.toString(), targetPath.toString());
        #else
            throw "Operation not supported on current target.";
        #end

        return targetFile;
    }


    /**
     * Moves the given file.
     *
     * <pre><code>
     * >>> File.of("target/foo.txt").writeString("HEY!") throws nothing
     * >>> File.of("target/foo.txt").moveTo("target/bar.txt") throws nothing
     * >>> File.of("target/bar.txt").moveTo("target/bar.txt") throws nothing
     * >>> File.of("target/foo.txt").path.exists()            == false
     * >>> File.of("target/bar.txt").path.exists()            == true
     *
     * >>> File.of("target/bar.txt").moveTo("") throws "[newPath] must not be null or empty!"
     * >>> File.of("target/bar.txt").delete()   == true
     * >>> File.of(""              ).moveTo("") throws "[path.filename] must not be null or empty!"
     * </code></pre>
     *
     * @param overwrite if set to true any file already existing at newPath will be deleted automatically
     * @param trimWhiteSpaces controls if leading/trailing whitespaces of path elements shall be removed automatically
     *
     * @return a File instance pointing to the new location
     */
    public function moveTo(newPath:Either2<String, Path>, overwrite = false, trimWhiteSpaces = true):File {
        assertValidPath();

        if (newPath == null)
            throw "[newPath] must not be null or empty!";

        var targetPath:Path = switch(newPath.value) {
            case a(str): Path.of(str, trimWhiteSpaces);
            case b(obj): obj;
        }

        if (targetPath.filename == "")
            throw "[newPath] must not be null or empty!";

        var targetFile = targetPath.toFile();

        if (targetPath.exists()) {

            if (path.getAbsolutePath() == targetPath.getAbsolutePath())
                return this;

            if (!overwrite)
                throw '[newPath] "$targetPath" already exists!';

            if (targetPath.isDirectory())
                throw '[newPath] "$targetPath" already exists and is a directory!';

            targetFile.delete();
        }

        #if (sys || macro || nodejs)
            FileSystem.rename(path.toString(), targetPath.toString());
        #elseif phantomjs
            js.phantomjs.FileSystem.move(path.toString(), targetPath.toString());
        #else
            throw "Operation not supported on current target.";
        #end

        return targetFile;
    }


    /**
     * Renames the given file within it's current parent directory.
     *
     * <pre><code>
     * >>> File.of("target/foo.txt").writeString("HEY!") throws nothing
     * >>> File.of("target/foo.txt").renameTo("bar.txt") throws nothing
     * >>> File.of("target/foo.txt").path.exists()       == false
     * >>> File.of("target/bar.txt").path.exists()       == true
     * >>> File.of("target/bar.txt").delete()            == true
     *
     * >>> File.of("target/foo.txt").renameTo("target/bar.txt") throws '[newFileName] "target/bar.txt" must not contain directory separators!'
     * >>> File.of("target/foo.txt").renameTo("")               throws "[newFileName] must not be null or empty!"
     * >>> File.of(""              ).renameTo("")               throws "[newFileName] must not be null or empty!"
     * </code></pre>
     *
     * @param overwrite if set to true any file already existing at newPath will be deleted automatically
     * @param newDirName the new directory name (NOT the full path!)
     *
     * @return a File instance pointing to the new location
     */
    public function renameTo(newFileName:String, overwrite = false):File {
        if (newFileName.isEmpty())
            throw "[newFileName] must not be null or empty!";

        if (newFileName.containsAny([Path.UnixPath.DIR_SEP, Path.WindowsPath.DIR_SEP]))
            throw '[newFileName] "$newFileName" must not contain directory separators!';

        if (path.parent == null)
            moveTo(newFileName, overwrite);

        return moveTo(path.parent.join(newFileName), overwrite);
    }


    /**
     * @return size in bytes
     */
    public function size():Int {
        if (!path.exists())
            throw '[path] "$path" doesn\'t exists!';

        #if (sys || macro || nodejs)
            var stat = sys.FileSystem.stat(path.toString());
            return stat.size;
        #elseif phantomjs
            return js.phantomjs.FileSystem.size(path.toString());
        #else
            throw "Operation not supported on current target.";
        #end
    }


    /**
     * Creates the file if it does not exist yet or updates the modification timestamp.
     *
     * <pre><code>
     * >>> File.of("target/touch.txt").path.exists() == false
     * >>> File.of("target/touch.txt").touch()       throws nothing
     * >>> File.of("target/touch.txt").path.exists() == true
     * >>> File.of("target/touch.txt").delete()      throws nothing
     * </code></pre>
     */
    public function touch():Void {
        assertValidPath(false);

        #if (sys || macro || nodejs)
            var exists = path.exists();
            if (path.exists()) {
                if (hx.strings.internal.OS.isWindows) {
                    Sys.command('copy /b "${path.toString()}"+,,'); // https://superuser.com/a/764721
                } else {
                    Sys.command('touch "${path.toString()}"');
                }
            } else {
                writeString("", false);
            }
        #elseif phantomjs
            js.phantomjs.FileSystem.touch(path.toString());
        #else
            throw "Operation not supported on current target.";
        #end
    }


    public function writeBytes(content:haxe.io.Bytes, overwrite = true):Void {

        assertValidPath(false);

        if (path.exists() && !overwrite)
            throw '[path] "$path" already exists!';

        if (content == null)
            return;

        #if (sys || macro || nodejs)
            sys.io.File.saveBytes(path.toString(), content);
        #elseif phantomjs
            js.phantomjs.FileSystem.write(path.toString(), content.toString(), "w");
        #else
            throw "Operation not supported on current target.";
        #end
    }


    /**
     * <pre><code>
     * >>> File.of("target/test.txt").writeString("HEY!")                 throws nothing
     * >>> File.of("target/test.txt").readAsString().indexOf("HEY!") > -1 == true
     * >>> File.of("target/test.txt").writeString("HEY!", false)          throws '[path] "target' + Path.of("").dirSep + 'test.txt" already exists!'
     * >>> File.of("target/test.txt").delete()                            throws nothing
     * >>> File.of(""               ).writeString("")                     throws "[path.filename] must not be null or empty!"
     * </code></pre>
     */
    public function writeString(content:String, overwrite = true):Void {

        assertValidPath(false);

        if (path.exists() && !overwrite)
            throw '[path] "$path" already exists!';

        if (content == null)
            return;

        #if (sys || macro || nodejs)
            sys.io.File.saveContent(path.toString(), content);
        #elseif phantomjs
            js.phantomjs.FileSystem.write(path.toString(), content, "w");
        #else
            throw "Operation not supported on current target.";
        #end
    }


    /**
      * @return the file's path
      */
    inline
    public function toString():String {
        return path.toString();
    }
}


enum FileWriteMode {
    REPLACE;
    #if (haxe_ver >= 4.0)
    UPDATE;
    #end
    APPEND;
}