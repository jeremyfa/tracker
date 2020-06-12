package tracker;

import haxe.ds.Map;
import haxe.ds.StringMap;
import haxe.ds.IntMap;
import haxe.DynamicAccess;
import tracker.Tracker.backend;
import haxe.rtti.Meta;

#if tracker_ceramic
import ceramic.Entity;
#end

using StringTools;

@:allow(tracker.SerializeModel)
@:allow(tracker.SaveModel)
class Serialize {

    public static var customHxSerialize:Dynamic->String = null;

    public static var customHxDeserialize:String->Dynamic = null;

    public static function serialize(serializable:Serializable):String {

        _serializedMap = new Map();

        var serialized = serializeValue(serializable);

        var s = new haxe.Serializer();
        s.serialize(serialized);
        s.serialize(_serializedMap);
        var result = s.toString();

        _serializedMap = null;

        return result;

    }

    public static function deserialize(serializable:Serializable, data:String):Void {

        var u = new haxe.Unserializer(data);
        var serialized = u.unserialize();
        _serializedMap = u.unserialize();
        _deserializedMap = new Map();

        var deserialized = deserializeValue(serialized, serializable);

        _deserializedMap = null;
        _serializedMap = null;

    }

/// Internal

    static var _serializedMap:Map<String,{ id:String, type:String, props:Dynamic }> = null;

    static var _deserializedMap:Map<String,Serializable> = null;

    static var _deserializedCacheMap:Map<String,Serializable> = null;

    static var _onAddSerializable:Serializable->Void = null;

    static var _onCheckSerializable:Serializable->Void = null;

    static var _appendSerialize:Bool = false;

    static function serializeValue(value:Dynamic):Dynamic {

        if (value == null) return null;
        if (_serializedMap == null) return null;

        // Ensure we don't serialize anything that got destroyed
        if (Std.is(value, Entity)) {
            var entity:Entity = cast value;
            if (entity.destroyed) {
                backend.error('Entity destroyed: $entity');
                return null;
            }
        }

        if (Std.is(value, Serializable)) {

            var clazz = Type.getClass(value);
            var props:Dynamic = {};
            var id = value._serializeId;

            Assert.assert(id != null, 'Serializable id must not be null');

            if (_deserializedMap != null) {
                _deserializedMap.set(id, value);
            }

            if (_onCheckSerializable != null) {
                _onCheckSerializable(value);
            }

            if (_serializedMap.exists(id)) {
                return { id: id };
            }

            var result = {
                id: id,
                type: Type.getClassName(clazz),
                props: {}
            };

            _serializedMap.set(id, result);

            var serializableInstance:Serializable = cast value;
            @:privateAccess serializableInstance.willSerialize();

            var prefixLen = 'unobserved'.length;
            var parentClazz = clazz;
            while (parentClazz != null) {
                var fieldsMeta = Meta.getFields(parentClazz);
                for (fieldRealName in Reflect.fields(fieldsMeta)) {
                    var fieldInfo = Reflect.field(fieldsMeta, fieldRealName);
    
                    if (Reflect.hasField(fieldInfo, 'serialize')) {
                        var fieldName = fieldRealName;
                        if (fieldName.startsWith('unobserved')) {
                            fieldName = fieldName.charAt(prefixLen).toLowerCase() + fieldName.substr(prefixLen + 1);
                        }
    
                        var originalValue = Extensions.getProperty(value, fieldRealName);
                        var val = serializeValue(originalValue);
                        Reflect.setField(result.props, fieldName, val);
                    }
                }
                parentClazz = Type.getSuperClass(parentClazz);
                if (parentClazz != null && Type.getClassName(parentClazz) == 'tracker.Model')
                    break;
            }

            if (_onAddSerializable != null) {
                _onAddSerializable(value);
            }

            return { id: id };

        }
        else if (Std.is(value, Array)) {

            var result:Array<Dynamic> = [];

            var array:Array<Dynamic> = value;
            for (item in array) {
                result.push(serializeValue(item));
            }

            return result;

        }
        else if (Std.is(value, String) || Std.is(value, Int) || Std.is(value, Float) || Std.is(value, Bool)) {

            return value;

        }
        else {

            switch (Type.typeof(value)) {
                case null:
                default:
                case TClass(c):
                    switch (#if (neko || cs || python) Type.getClassName(c) #else c #end) {
                        case null:
                        default:
                        case #if (neko || cs || python) "haxe.ds.StringMap" #else cast StringMap #end:
                            var values:Array<Dynamic> = [];
                            var result:Dynamic = {
                                sm: values
                            };
                            var mapValue:StringMap<Dynamic> = value;
                            for (key in mapValue.keys()) {
                                values.push(key);
                                values.push(serializeValue(mapValue.get(key)));
                            }
                            return result;
                        case #if (neko || cs || python) "haxe.ds.IntMap" #else cast IntMap #end:
                            var values:Array<Dynamic> = [];
                            var result:Dynamic = {
                                im: values
                            };
                            var mapValue:IntMap<Dynamic> = value;
                            for (key in mapValue.keys()) {
                                values.push(key);
                                values.push(serializeValue(mapValue.get(key)));
                            }
                            return result;
                    }
            }
        }

        // If nothing else worked, fallback to regular haxe serialization
        if (customHxSerialize != null) {
            return { hx : customHxSerialize(value) };
        }
        else {
            // Use Haxe's built in serializer as a fallback
            var serializer = new haxe.Serializer();
            serializer.useCache = true;
            serializer.serialize(value);

            return { hx: serializer.toString() };
        }

    }

    static function deserializeValue(value:Dynamic, ?serializable:Serializable):Dynamic {

        if (value == null) return null;
        if (_serializedMap == null) return null;
        if (_deserializedMap == null) return null;

        if (Std.is(value, Array)) {

            var result:Array<Dynamic> = [];

            var array:Array<Dynamic> = value;
            for (item in array) {
                result.push(deserializeValue(item));
            }

            return result;

        }
        else if (Std.is(value, String) || Std.is(value, Int) || Std.is(value, Float) || Std.is(value, Bool)) {

            return value;

        }
        else if (value.id != null) {

            if (_deserializedMap.exists(value.id)) {
                return _deserializedMap.get(value.id);
            }
            else if (_serializedMap.exists(value.id)) {

                var info = _serializedMap.get(value.id);
                
                var clazz = Type.resolveClass(info.type);
                if (clazz == null) {
                    backend.warning('Failed to resolve class for serialized type: ' + info.type);
                    return null;
                }

                if (serializable != null && Type.getClass(serializable) != clazz) {
                    throw 'Type mismatch when deserializing object expected $clazz, got ' + Type.getClass(serializable);
                }

                // Create instance (without calling constructor)
                var instance:Serializable = null;
                var reusingInstance = false;
                if (_deserializedCacheMap != null && _deserializedCacheMap.exists(value.id)) {
                    instance = _deserializedCacheMap.get(value.id);
                    reusingInstance = true;
                }
                else {
                    instance = serializable != null && Type.getClass(serializable) == clazz ? serializable : Type.createEmptyInstance(clazz);
                }

                Assert.assert(instance != null, 'Created empty instance should not be null');

                // Add instance in mapping
                instance._serializeId = value.id;
                _deserializedMap.set(value.id, instance);

                // Iterate over each serializable field and either put a default value
                // or the one provided by serialized data.
                //
                var fieldsMeta = Meta.getFields(clazz);
                var prefixLen = 'unobserved'.length;
                var instanceFields = new Map<String,Bool>();
                for (field in Type.getInstanceFields(clazz)) {
                    instanceFields.set(field, true);
                }
                var parentClazz = Type.getSuperClass(clazz);
                var parentFieldsMeta = null;
                while (parentClazz != null) {
                    if (parentFieldsMeta == null)
                        parentFieldsMeta = [];
                    parentFieldsMeta.push(Meta.getFields(parentClazz));
                    if (Type.getClassName(parentClazz) == 'tracker.Model') {
                        break;
                    }
                    for (field in Type.getInstanceFields(parentClazz)) {
                        instanceFields.set(field, true);
                    }
                    parentClazz = Type.getSuperClass(parentClazz);
                }

                for (fieldRealName in instanceFields.keys()) {

                    var fieldInfo = Reflect.field(fieldsMeta, fieldRealName);
                    if (fieldInfo == null && parentFieldsMeta != null) {
                        for (i in 0...parentFieldsMeta.length) {
                            fieldInfo = Reflect.field(parentFieldsMeta[i], fieldRealName);
                            if (fieldInfo != null)
                                break;
                        }
                    }
                    var hasSerialize = fieldInfo != null && Reflect.hasField(fieldInfo, 'serialize');

                    var fieldName = fieldRealName;
                    if (fieldName.startsWith('unobserved')) {
                        fieldName = fieldName.charAt(prefixLen).toLowerCase() + fieldName.substr(prefixLen + 1);
                    }

                    if (hasSerialize && Reflect.hasField(info.props, fieldName)) {
                        // Value provided by data, use it
                        var val = deserializeValue(Reflect.field(info.props, fieldName));
                        Extensions.setProperty(instance, reusingInstance ? fieldName : fieldRealName, val);
                    }
                    else if (!reusingInstance && instanceFields.exists('_default_' + fieldName)) {
                        // No value in data, but a default one for this class, use it
                        var val = Reflect.callMethod(instance, Reflect.field(instance, '_default_' + fieldName), []);
                        Extensions.setProperty(instance, fieldRealName, val);
                    }
                }

                @:privateAccess instance.didDeserialize();

                return instance;

            }
            else {
                return null;
            }

        }
        else if (value.sm != null) {

            var values:Array<Dynamic> = value.sm;
            var i = 0;
            var result = new StringMap();
            while (i < values.length) {
                result.set(values[i], deserializeValue(values[i+1]));
                i += 2;
            }
            
            return result;

        }
        else if (value.im != null) {

            var values:Array<Dynamic> = value.im;
            var i = 0;
            var result = new IntMap();
            while (i < values.length) {
                result.set(values[i], deserializeValue(values[i+1]));
                i += 2;
            }
            
            return result;

        }
        else if (value.hx != null) {

            if (customHxDeserialize != null) {
                return customHxDeserialize(value.hx);
            } else {
                var u = new haxe.Unserializer(value.hx);
                try {
                    return u.unserialize();
                }
                catch (e:Dynamic) {
                    backend.warning('Failed to deserialize: ' + value.hx);
                    return null;
                }
            }

        }
        else {

            return null;

        }

    }

}
