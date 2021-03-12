package tracker;

/** A bunch of static extensions to make life easier. */
class Extensions<T> {

/// Array extensions

    #if !tracker_debug_unsafe inline #end public static function unsafeGet<T>(array:Array<T>, index:Int):T {
#if tracker_debug_unsafe
        if (index < 0 || index >= array.length) throw 'Invalid unsafeGet: index=$index length=${array.length}';
#end
#if cpp
        return cpp.NativeArray.unsafeGet(array, index);
#elseif cs
        return cast untyped __cs__('{0}.__a[{1}]', array, index);
#else
        return array[index];
#end
    }

    #if !tracker_debug_unsafe inline #end public static function unsafeSet<T>(array:Array<T>, index:Int, value:T):Void {
#if tracker_debug_unsafe
        if (index < 0 || index >= array.length) throw 'Invalid unsafeSet: index=$index length=${array.length}';
#end
#if cpp
        cpp.NativeArray.unsafeSet(array, index, value);
#elseif cs
        return cast untyped __cs__('{0}.__a[{1}] = {2}', array, index, value);
#else
        array[index] = value;
#end
    }

    #if !debug inline #end public static function setArrayLength<T>(array:Array<T>, length:Int):Void {
        if (array.length != length) {
#if cpp
            untyped array.__SetSize(length);
#else
            if (array.length > length) {
                array.splice(length, array.length - length);
            }
            else {
                var dArray:Array<Dynamic> = array;
                dArray[length - 1] = null;
            }
#end
        }
    }

/// Generic extensions

        @:noCompletion
        inline public static function setProperty<T>(instance:T, field:String, value:Dynamic):Void {

            Reflect.setProperty(instance, field, value);

        }

        @:noCompletion
        inline public static function getProperty<T>(instance:T, field:String):Dynamic {

            return Reflect.getProperty(instance, field);

        }

}
