package tracker;

using StringTools;

@:keep
@:keepSub
class Model extends #if tracker_ceramic ceramic.Entity #else Entity #end implements Observable implements Serializable {

/// Events

    @event function _modelDirty(model:Model);

/// Components

    @component public var serializer:SerializeModel;

    @component public var sharer:ShareModel;

/// Properties

    public var dirty(default,set):Bool = false;

    inline function set_dirty(dirty:Bool):Bool {
        if (dirty == this.dirty) return dirty;
        this.dirty = dirty;
        if (dirty) {
            emitModelDirty(this);
        }
        return dirty;
    }

/// Lifecycle

    public function new(#if tracker_debug_entity_allocs ?pos:haxe.PosInfos #end) {

        super(#if tracker_debug_entity_allocs pos #end);

    }

    /** Called right before the object will be serialized. */
    function willSerialize():Void {

    }

    /** Called right after the object has been deserialized. Could be useful to override it to check data integrity
        when running a newer model version etc... */
    function didDeserialize():Void {

    }

    /**
     * Called right before the object is destroyed because it is not used anymore.
     * @return `true` (default) if the destroy should happen or not
     */
    function serializeShouldDestroy():Bool {

        return true;

    }

/// Haxe built in serializer extension

    @:keep
    function hxSerialize(s:haxe.Serializer) {
        s.serialize(@:privateAccess Serialize.serializeValue(this));
    }

    @:keep
    function hxUnserialize(u:haxe.Unserializer) {
        @:privateAccess Serialize.deserializeValue(u.unserialize(), this);
    }

}
