package tracker;

using tracker.Extensions;

/**
 * Utilities to schedule code "almost" immediately.
 */
class Immediate {

    public function new() {}

/// Immediate update system

    /**
     * Array of callbacks to be executed immediately before the next frame.
     * These callbacks are guaranteed to run before visual updates and rendering.
     */
    var immediateCallbacks:Array<Void->Void> = [];

    /**
     * Current capacity of immediate callbacks array to optimize array operations
     */
    var immediateCallbacksCapacity:Int = 0;

    /**
     * Current number of pending immediate callbacks
     */
    var immediateCallbacksLen:Int = 0;

    /**
     * Array of callbacks to be executed after all immediate callbacks are done
     */
    var postFlushImmediateCallbacks:Array<Void->Void> = [];

    /**
     * Current capacity of post flush immediate callbacks array
     */
    var postFlushImmediateCallbacksCapacity:Int = 0;

    /**
     * Current number of pending post flush immediate callbacks
     */
    var postFlushImmediateCallbacksLen:Int = 0;

    @:noCompletion public var loaders:Array<(done:()->Void)->Void> = [];

    /**
     * Schedule immediate callback that is garanteed to be executed before the next time frame
     * (before elements are drawn onto screen)
     * @param owner Owner of this callback, allowing to cancel callback if owner is destroyed
     * @param handleImmediate The callback to execute
     */
    extern inline overload public function onceImmediate(#if tracker_ceramic owner:ceramic.Entity #else owner:tracker.Entity #end , handleImmediate:Void->Void #if tracker_debug_immediate , ?pos:haxe.PosInfos #end):Void {

        _onceImmediateWithOwner(owner, handleImmediate #if tracker_debug_immediate , pos #end);

    }

    /**
     * Schedule immediate callback that is garanteed to be executed before the next time frame
     * (before elements are drawn onto screen)
     * @param handleImmediate The callback to execute
     */
    extern inline overload public function onceImmediate(handleImmediate:Void->Void #if tracker_debug_immediate , ?pos:haxe.PosInfos #end):Void {

        _onceImmediate(handleImmediate #if tracker_debug_immediate , pos #end);

    }

    function _onceImmediateWithOwner(#if tracker_ceramic owner:ceramic.Entity #else owner:tracker.Entity #end , handleImmediate:Void->Void #if tracker_debug_immediate , ?pos:haxe.PosInfos #end):Void {

        _onceImmediate(function() {
            if (owner == null || !owner.destroyed) {
                handleImmediate();
            }
        } #if tracker_debug_immediate , pos #end);

    }

    function _onceImmediate(handleImmediate:Void->Void #if tracker_debug_immediate , ?pos:haxe.PosInfos #end):Void {

        if (handleImmediate == null) {
            throw 'Immediate callback should not be null!';
        }

        #if tracker_debug_immediate
        immediateCallbacks[immediateCallbacksLen++] = function() {
            haxe.Log.trace('immediate flush', pos);
            handleImmediate();
        };
        #else
        if (immediateCallbacksLen < immediateCallbacksCapacity) {
            immediateCallbacks.unsafeSet(immediateCallbacksLen, handleImmediate);
            immediateCallbacksLen++;
        }
        else {
            immediateCallbacks[immediateCallbacksLen++] = handleImmediate;
            immediateCallbacksCapacity++;
        }
        #end

    }

    /**
     * Schedule callback that is garanteed to be executed when no immediate callback are pending anymore.
     * @param owner Owner of this callback, allowing to cancel callback if owner is destroyed
     * @param handlePostFlushImmediate The callback to execute
     * @param defer if `true` (default), will box this call into an immediate callback
     */
    extern inline overload public function oncePostFlushImmediate(#if tracker_ceramic owner:ceramic.Entity #else owner:tracker.Entity #end , handlePostFlushImmediate:Void->Void, defer:Bool = true):Void {

        _oncePostFlushImmediateWithOwner(owner, handlePostFlushImmediate, defer);

    }

    /**
     * Schedule callback that is garanteed to be executed when no immediate callback are pending anymore.
     * @param handlePostFlushImmediate The callback to execute
     * @param defer if `true` (default), will box this call into an immediate callback
     */
    extern inline overload public function oncePostFlushImmediate(handlePostFlushImmediate:Void->Void, defer:Bool = true):Void {

        _oncePostFlushImmediate(handlePostFlushImmediate, defer);

    }

    function _oncePostFlushImmediateWithOwner(#if tracker_ceramic owner:ceramic.Entity #else owner:tracker.Entity #end , handlePostFlushImmediate:Void->Void, defer:Bool):Void {

        _oncePostFlushImmediate(function() {
            if (owner == null || !owner.destroyed) {
                handlePostFlushImmediate();
            }
        }, defer);

    }

    /**
     * Schedule callback that is garanteed to be executed when no immediate callback are pending anymore.
     * @param handlePostFlushImmediate The callback to execute
     * @param defer if `true` (default), will box this call into an immediate callback
     */
    function _oncePostFlushImmediate(handlePostFlushImmediate:Void->Void, defer:Bool):Void {

        if (!defer) {
            if (immediateCallbacksLen == 0) {
                handlePostFlushImmediate();
            }
            else {

                if (postFlushImmediateCallbacksLen < postFlushImmediateCallbacksCapacity) {
                    postFlushImmediateCallbacks.unsafeSet(postFlushImmediateCallbacksLen, handlePostFlushImmediate);
                    postFlushImmediateCallbacksLen++;
                }
                else {
                    postFlushImmediateCallbacks[postFlushImmediateCallbacksLen++] = handlePostFlushImmediate;
                    postFlushImmediateCallbacksCapacity++;
                }
            }
        }
        else {
            Tracker.backend.onceImmediate(function() {
                oncePostFlushImmediate(handlePostFlushImmediate, false);
            });
        }

    }

    /**
     * Execute and flush every awaiting immediate callback, including the ones that
     * could have been added with `onceImmediate()` after executing the existing callbacks.
     * @return `true` if anything was flushed
     */
    public function flushImmediate():Bool {

        var didFlush = false;

        // Immediate callbacks
        while (immediateCallbacksLen > 0) {

            didFlush = true;

            #if tracker_ceramic
            var pool = ceramic.ArrayPool.pool(immediateCallbacksLen);
            #else
            var pool = tracker.ArrayPool.pool(immediateCallbacksLen);
            #end
            var callbacks = pool.get();
            var len = immediateCallbacksLen;
            immediateCallbacksLen = 0;

            for (i in 0...len) {
                callbacks.set(i, immediateCallbacks.unsafeGet(i));
                immediateCallbacks.unsafeSet(i, null);
            }

            for (i in 0...len) {
                var cb:Dynamic = callbacks.get(i);
                cb();
            }

            pool.release(callbacks);

        }

        // Post flush immediate callbacks
        if (postFlushImmediateCallbacksLen > 0) {

            #if tracker_ceramic
            var pool = ceramic.ArrayPool.pool(postFlushImmediateCallbacksLen);
            #else
            var pool = tracker.ArrayPool.pool(postFlushImmediateCallbacksLen);
            #end
            var callbacks = pool.get();
            var len = postFlushImmediateCallbacksLen;
            postFlushImmediateCallbacksLen = 0;

            for (i in 0...len) {
                callbacks.set(i, postFlushImmediateCallbacks.unsafeGet(i));
                postFlushImmediateCallbacks.unsafeSet(i, null);
            }

            for (i in 0...len) {
                var cb:Dynamic = callbacks.get(i);
                cb();
            }

            pool.release(callbacks);

        }

        return didFlush;

    }

}