package tracker;

using tracker.Extensions;

class DefaultBackend #if !tracker_custom_backend implements Backend #end {

    public function new() {

    }

    var immediateCallbacks:Array<Void->Void> = [];

    var immediateCallbacksLen:Int = 0;

    var flushingImmediateCallbacks:Bool = false;

    #if (tracker_web_immediate && !tracker_manual_flush)
    var flushImmediateScheduled:Bool = false;
    #end

    /**
     * Schedule immediate callback.
     * @param handleImmediate the callback to schedule
     */
    public function onceImmediate(handleImmediate:Void->Void):Void {

        immediateCallbacks[immediateCallbacksLen++] = handleImmediate;

        #if !tracker_manual_flush
        #if tracker_web_immediate
        if (!flushImmediateScheduled) {
            flushImmediateScheduled = true;
            js.Syntax.code("queueMicrotask({0})", () -> {
                flushImmediate();
                flushImmediateScheduled = false;
            });
        }
        #else
        if (!flushingImmediateCallbacks) {
            flushImmediate();
        }
        #end
        #end

    }

    /** Execute and flush every awaiting immediate callback, including the ones that
        could have been added with `onceImmediate()` after executing the existing callbacks. */
    #if tracker_manual_flush public #end function flushImmediate():Bool {

        flushingImmediateCallbacks = true;

        var didFlush = false;

        // Immediate callbacks
        while (immediateCallbacksLen > 0) {

            didFlush = true;

            var pool = ArrayPool.pool(immediateCallbacksLen);
            var callbacks = pool.get();
            var len = immediateCallbacksLen;
            immediateCallbacksLen = 0;

            for (i in 0...len) {
                callbacks.set(i, immediateCallbacks.unsafeGet(i));
                immediateCallbacks[i] = null;
            }

            for (i in 0...len) {
                var cb:Void->Void = callbacks.get(i);
                cb();
            }

            pool.release(callbacks);

        }

        flushingImmediateCallbacks = false;

        return didFlush;

    }

    #if !tracker_web_storage
    var stringData:Map<String,String> = new Map();
    #end

    /**
     * Read a string for the given key
     * @param key the key to use
     * @return String or null of no string was found
     */
    public function readString(key:String):String {

        #if tracker_web_storage
        return webReadString(key);
        #else
        return stringData.get(key);
        #end

    }

    /**
     * Save a string for the given key
     * @param key the key to use
     * @param str the string to save
     * @return Bool `true` if the save was successful
     */
    public function saveString(key:String, str:String):Bool {

        #if tracker_web_storage
        return webSaveString(key, str);
        #else
        stringData.set(key, str);

        return true;
        #end

    }

    /**
     * Append a string on the given key. If the key doesn't exist,
     * creates a new one with the string to append.
     * @param key the key to use
     * @param str the string to append
     * @return Bool `true` if the save was successful
     */
    public function appendString(key:String, str:String):Bool {

        #if tracker_web_storage
        return webAppendString(key, str);
        #else
        var existingStr = stringData.get(key);
        if (existingStr != null) {
            stringData.set(key, existingStr + str);
        }
        else {
            stringData.set(key, str);
        }

        return true;
        #end

    }

    #if tracker_web_storage

    function webSaveString(key:String, str:String):Bool {

        try {
            var storage = js.Browser.window.localStorage;
            if (storage == null) {
                error('Cannot save string: localStorage not supported on this browser');
                return false;
            }

            storage.setItem(key, HashedString.encode(str));
        }
        catch (e:Dynamic) {
            error('Failed to save string (key=$key): ' + e);
            return false;
        }

        return true;

    }

    function webAppendString(key:String, str:String):Bool {

        try {
            var storage = js.Browser.window.localStorage;
            if (storage == null) {
                error('Cannot append string: localStorage not supported on this browser');
                return false;
            }

            var existing = storage.getItem(key);
            if (existing == null) {
                storage.setItem(key, HashedString.encode(str));
            }
            else {
                storage.setItem(key, existing + HashedString.encode(str));
            }
        }
        catch (e:Dynamic) {
            error('Failed to append string (key=$key): ' + e);
            return false;
        }

        return true;

    }

    function webReadString(key:String):String {

        try {
            var storage = js.Browser.window.localStorage;
            if (storage == null) {
                error('Cannot read string: localStorage not supported on this browser');
                return null;
            }

            var str = storage.getItem(key);
            return str != null ? HashedString.decode(str) : null;
        }
        catch (e:Dynamic) {
            error('Failed to read string (key=$key): ' + e);
            return null;
        }

    }

    #end

    /**
     * Log a warning message
     * @param message the warning message
     */
    public function warning(message:Dynamic, ?pos:haxe.PosInfos):Void {

        haxe.Log.trace('[warning] ' + message, pos);

    }

    /**
     * Log an error message
     * @param error the error message
     */
    public function error(error:Dynamic, ?pos:haxe.PosInfos):Void {

        haxe.Log.trace('[error] ' + error, pos);

    }

    /**
     * Log a success message
     * @param message the success message
     */
    public function success(message:Dynamic, ?pos:haxe.PosInfos):Void {

        haxe.Log.trace('[success] ' + message, pos);

    }

    /**
     * Run the given callback in background, if there is any background thread available
     * on this backend. Run it on the main thread otherwise like any other code
     * @param callback
     */
    public function runInBackground(callback:Void->Void):Void {

        onceImmediate(callback);

    }

    /**
     * Run the given callback in main thread
     * @param callback
     */
    public function runInMain(callback:Void->Void):Void {

        onceImmediate(callback);

    }

    /**
     * Execute a callback periodically at the given interval in seconds.
     * @param owner The entity that owns this interval
     * @param seconds The time in seconds between each call
     * @param callback The callback to call
     * @return ()->Void A callback to cancel the interval
     */
    public function interval(owner:Entity, seconds:Float, callback:Void->Void):Void->Void {

        var timer = new haxe.Timer(Math.round(seconds * 1000));
        timer.run = function() {
            if (owner == null || !owner.destroyed) {
                callback();
            }
            else {
                timer.stop();
            }
        };
        return timer.stop;

    }

    /**
     * Execute a callback after the given delay in seconds.
     * @param owner The entity that owns this delayed call
     * @param seconds The time in seconds of delay before the call
     * @param callback The callback to call
     * @return ()->Void A callback to cancel the delayed call
     */
    public function delay(owner:Entity, seconds:Float, callback:Void->Void):Void->Void {

        var timer = new haxe.Timer(Math.round(seconds * 1000));
        timer.run = function() {
            timer.stop();
            if (owner == null || !owner.destroyed) {
                callback();
            }
        };
        return timer.stop;

    }

    /**
     * Get storage directory (if any available)
     * @return directory as string or null if nothing available
     */
    inline public function storageDirectory():Null<String> {

        return null;

    }

    /**
     * Joins all paths in `paths` together.
     * @return joined paths as string
     */
    inline public function pathJoin(paths:Array<String>):String {

        return haxe.io.Path.join(paths);

    }

}
