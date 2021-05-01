package tracker;

using StringTools;

@:keep
@:keepSub
class Model extends #if tracker_ceramic ceramic.Entity #else Entity #end implements Observable implements Serializable {

/// Events

    @event function _modelDirty(model:Model);

/// Components

    @component public var serializer:SerializeModel;

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

/// Print

    override function toString():String {

        return '' + _toDynamic(this);

    }

    static final TO_DYNAMIC_MAX_STACK:Int = 8;

    static var _toDynamicUsed:Array<Dynamic> = null;

    static var _toDynamicStack:Int = 0;

    static function _toDynamic(obj:Dynamic):Dynamic {

        var prevAutorun = Autorun.current;
        Autorun.current = null;

        var didInitUsed = false;
        if (_toDynamicUsed == null) {
            didInitUsed = true;
            _toDynamicUsed = [];
            _toDynamicStack = 0;
        }
        else {
            _toDynamicStack++;
        }

        var result:Dynamic = {};

        for (key in Reflect.fields(obj)) {

            if (key.startsWith('_')) continue;
            if (key.endsWith('Autoruns')) continue;

            var displayKey = key;
            if (displayKey.startsWith('unobserved')) {
                displayKey = displayKey.charAt(10).toLowerCase() + displayKey.substring(11);
            }

            var value = Reflect.field(obj, key);
            switch Type.typeof(value) {
                case TNull | TInt | TFloat | TBool | TFunction | TUnknown | TEnum(_):
                    Reflect.setField(result, displayKey, value);
                case TObject | TClass(_):
                    if (Std.is(value, String)) {
                        Reflect.setField(result, displayKey, value);
                    }
                    else {
                        if (_toDynamicUsed.indexOf(value) != -1 || _toDynamicStack > TO_DYNAMIC_MAX_STACK) {
                            Reflect.setField(result, displayKey, '<...>');
                        }
                        else {
                            _toDynamicUsed.push(value);
                            Reflect.setField(result, displayKey, _toDynamic(value));
                        }
                    }
            }
        }

        if (didInitUsed) {
            _toDynamicUsed = null;
            _toDynamicStack = 0;
        }
        else {
            _toDynamicStack--;
        }

        Autorun.current = prevAutorun;

        return result;

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
