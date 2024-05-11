package tracker;

using tracker.Extensions;

class Equal {

    /**
     * Equality check (deep equality only working on arrays for now)
     * @param a
     * @param b
     * @return Bool
     */
    public static function equal(a:Dynamic, b:Dynamic):Bool {

        if (a == b)
            return true;

        if (Std.isOfType(a, Array)) {
            if (Std.isOfType(b, Array)) {
                return _arrayEqual(a, b);
            }
            return false;
        }
        else if (Reflect.isObject(a) && Type.getClass(a) == null) {
            if (Reflect.isObject(b) && Type.getClass(b) == null) {
                return objectFieldsEqual(a, b);
            }
            return false;
        }

        return false;

    }

    public static function objectFieldsEqual(a:Any, b:Any):Bool {
        for (field in Reflect.fields(a)) {
            if (!Reflect.hasField(b, field) || !equal(Reflect.field(a, field), Reflect.field(b, field))) {
                return false;
            }
        }
        for (field in Reflect.fields(b)) {
            if (!Reflect.hasField(a, field)) {
                return false;
            }
        }
        return true;
    }

    #if cs
    public extern inline static overload function arrayEqual(a:Array<String>, b:Array<String>):Bool {
        var aDyn:Any = a;
        var bDyn:Any = b;
        return _arrayEqual(cast aDyn, cast bDyn);
    }
    #end

    public extern inline static overload function arrayEqual(a:Array<Any>, b:Array<Any>):Bool {
        return _arrayEqual(a, b);
    }

    static function _arrayEqual(a:Array<Any>, b:Array<Any>):Bool {

        var lenA = a.length;
        var lenB = b.length;
        if (lenA != lenB)
            return false;
        for (i in 0...lenA) {
            if (a.unsafeGet(i) != b.unsafeGet(i)) {
                return false;
            }
        }
        return true;

    }

}