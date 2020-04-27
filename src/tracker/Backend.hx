package tracker;

#if !tracker_custom_backend

interface Backend {

    /**
     * Schedule immediate callback. These callbacks need to be flushed at some point by the backend
     * @param handleImmediate the callback to schedule
     */
    function onceImmediate(handleImmediate:Void->Void):Void;

    /**
     * Read a string for the given key
     * @param key the key to use
     * @return String or null of no string was found
     */
    function readString(key:String):String;

    /**
     * Save a string for the given key
     * @param key the key to use
     * @param str the string to save
     * @return Bool `true` if the save was successful
     */
    function saveString(key:String, str:String):Bool;

    /**
     * Append a string on the given key. If the key doesn't exist,
     * creates a new one with the string to append.
     * @param key the key to use
     * @param str the string to append
     * @return Bool `true` if the save was successful
     */
    function appendString(key:String, str:String):Bool;

    /**
     * Log a warning message
     * @param message the warning message
     */
    function warning(message:Dynamic, ?pos:haxe.PosInfos):Void;

    /**
     * Log an error message
     * @param error the error message
     */
    function error(error:Dynamic, ?pos:haxe.PosInfos):Void;

    /**
     * Log a success message
     * @param message the success message
     */
    function success(message:Dynamic, ?pos:haxe.PosInfos):Void;

    /**
     * Run the given callback in background, if there is any background thread available
     * on this backend. Run it on the main thread otherwise like any other code
     * @param callback 
     */
    function runInBackground(callback:Void->Void):Void;

    /**
     * Run the given callback in main thread
     * @param callback 
     */
    function runInMain(callback:Void->Void):Void;

    /**
     * Execute a callback periodically at the given interval in seconds.
     * @param owner The entity that owns this interval
     * @param seconds The time in seconds between each call
     * @param callback The callback to call
     * @return Void->Void A callback to cancel the interval
     */
    function interval(owner:Entity, seconds:Float, callback:Void->Void):Void->Void;

    /**
     * Execute a callback after the given delay in seconds.
     * @param owner The entity that owns this delayed call
     * @param seconds The time in seconds of delay before the call
     * @param callback The callback to call
     * @return Void->Void A callback to cancel the delayed call
     */
    function delay(owner:Entity, seconds:Float, callback:Void->Void):Void->Void;

}

#end
