package tracker;

/**
 * Anything that can own an event handler, an autorun, a timer or a tween.
 *
 * An owner has a lifecycle: when it is destroyed, every subscription made
 * with it as `owner` is removed. Entities implement this interface, but a
 * lighter object can implement it too (for instance an object whose
 * lifecycle is carried by a host entity) and pass `this` wherever an owner
 * is expected.
 */
interface Owner {

    /**
     * Whether this owner has been destroyed. Nothing can be bound to a
     * destroyed owner.
     */
    var destroyed(get, never):Bool;

    /**
     * Call `handler` once, when this owner gets destroyed. The handler
     * receives the destroyed owner.
     */
    function onceDestroy(#if tracker_optional_owner ?owner:Owner #else owner:Null<Owner> #end, handler:(Owner) -> Void #if tracker_debug_events , ?pos:haxe.PosInfos #end):Void;

    /**
     * Remove a handler previously bound with `onceDestroy()` (or `onDestroy()`).
     */
    function offDestroy(?handler:(Owner) -> Void):Void;

}
