package tracker;

import tracker.Tracker.backend;

/** Utility to serialize a model object (and its children) continuously and efficiently */
class SerializeModel extends #if tracker_ceramic ceramic.Entity #else Entity #end implements #if tracker_ceramic ceramic.Component #else tracker.Component #end {

/// Events

    /** Triggered when serialized data is updated.
        If `append` is true, the given string should be appended to the existing one. */
    @event function changeset(changeset:SerializeChangeset);

/// Settings

    public var checkInterval:Float = 1.0;

    public var compactInterval:Float = 60.0;

    public var destroyModelOnUntrack:Bool = true;

/// Properties

    public var serializedMap(default,null):Map<String,{ id:String, type:String, props:Dynamic }> = new Map();

    public var model(get,null):Model;
    inline function get_model():Model return entity;

    var entity:Model;

/// Lifecycle

    function bindAsComponent() {

        if (checkInterval > 0) {
            // Synchronize with real data at regular interval
            backend.interval(this, checkInterval, synchronize);
        }

        if (compactInterval > 0) {
            // Compact at regular interval
            backend.interval(this, compactInterval, compactIfNeeded);
        }

        // Track root model
        track(model);

        // Perform first compaction to get initial data
        compact();

    }

/// Public API

    /** Recompute the whole object tree instead of appending. This will untrack every object not on the model anymore
        and generate a new changeset with the whole serialized object tree. */
    public function compact(?done:String->Void):Void {

        var prevSerializedMap = serializedMap;

        Serialize._serializedMap = new Map();
        Serialize._onAddSerializable = function(serializable:Serializable) {

            if (Std.isOfType(serializable, Model)) {
                var model:Model = cast serializable;
                model.observedDirty = false;
                track(model);
            }

        };

        var serialized = Serialize.serializeValue(model);

        serializedMap = Serialize._serializedMap;

        Serialize._onAddSerializable = null;
        Serialize._serializedMap = null;

        cleanTrackingFromPrevSerializedMap(prevSerializedMap);

        var s = new haxe.Serializer();
        s.serialize(serialized);
        s.serialize(serializedMap);
        var data = s.toString();

        // Emit full changeset
        emitChangeset({ data: data, append: false });

        // Call done() callback if provided
        if (done != null) done(data);

    }

/// Internal

    var trackedModels:Map<String,Model> = new Map();

    var willCleanDestroyedTrackedModels:Bool = false;

    var dirtyModels:Map<String,Model> = new Map();

    var canCompact = false;

    var dirty:Bool = true;

    inline function track(model:Model) {

        if (!model.destroyed && !trackedModels.exists(model._serializeId)) {
            trackedModels.set(model._serializeId, model);
            model.onModelDirty(this, explicitModelDirty);
            model.onObservedDirty(this, modelDirty);
            model.onceDestroy(this, trackedModelDestroyed);
        }

    }

    inline function untrack(model:Model) {

        if (trackedModels.exists(model._serializeId)) {
            trackedModels.remove(model._serializeId);
            model.offModelDirty(explicitModelDirty);
            model.offObservedDirty(modelDirty);
            model.offDestroy(trackedModelDestroyed);
            if (destroyModelOnUntrack) {
                model.destroy();
            }
        }

    }

    function trackedModelDestroyed(_) {

        if (willCleanDestroyedTrackedModels) return;
        willCleanDestroyedTrackedModels = true;

        backend.onceImmediate(function() {

            var keys = [];
            for (key in trackedModels.keys()) {
                keys.push(key);
            }
            for (key in keys) {
                var model = trackedModels.get(key);
                if (model.destroyed) {
                    untrack(model);
                }
            }

            willCleanDestroyedTrackedModels = false;
        });

    }

    function cleanTrackingFromPrevSerializedMap(prevSerializedMap:Map<String,{ id:String, type:String, props:Dynamic }>) {

        var removedIds = [];

        for (key in prevSerializedMap.keys()) {
            if (!serializedMap.exists(key)) {
                removedIds.push(key);
            }
        }

        for (key in removedIds) {
            var model = trackedModels.get(key);
            if (model != null) {
                untrack(model);
            }
        }

    }

    function modelDirty(model:Model, fromSerializedField:Bool) {

        if (!fromSerializedField) {
            // If the observed object got dirty from a non-serialized field,
            // there is nothing to do. Just mark the model as `clean` and wait
            // for the next change.
            model.observedDirty = false;
            return;
        }

        dirtyModels.set(model._serializeId, model);
        dirty = true;

    }

    function explicitModelDirty(model:Model) {

        dirtyModels.set(model._serializeId, model);
        dirty = true;

    }

    /** Synchronize (expected to be called at regular intervals or when something important needs to be serialized) */
    public function synchronize() {

        if (!dirty) return;
        dirty = false;

        var toAppend = [];
        for (id in dirtyModels.keys()) {
            var model = dirtyModels.get(id);
            if (!model.destroyed && trackedModels.exists(model._serializeId)) {
                model.dirty = false;
                serializeModel(model, toAppend);
            }
        }
        dirtyModels = new Map();

        if (toAppend.length > 0) {
            var s = new haxe.Serializer();
            s.serialize(toAppend);
            var data = s.toString();

            // Can compact
            canCompact = true;

            // Emit changeset
            emitChangeset({ data: data, append: true });
        }

    }

    function compactIfNeeded() {

        if (canCompact) {
            canCompact = false;
            compact();
        }

    }

    inline function serializeModel(model:Model, toAppend:Array<{ id:String, type:String, props:Dynamic }>) {

        // Remove model from map to ensure it is re-serialized
        serializedMap.remove(model._serializeId);

        Serialize._serializedMap = serializedMap;
        Serialize._onCheckSerializable = function(serializable:Serializable) {

            var id = serializable._serializeId;
            var model = trackedModels.get(id);

            if (model != null) {
                if (model != serializable) {
                    // Replacing object with same id
                    serializedMap.remove(id);
                }
            }

        };
        Serialize._onAddSerializable = function(serializable:Serializable) {

            if (Std.isOfType(serializable, Model)) {

                var model:Model = cast serializable;
                model.observedDirty = false;
                toAppend.push(serializedMap.get(model._serializeId));

                track(model);
            }

        };

        Serialize.serializeValue(model);

        Serialize._onCheckSerializable = null;
        Serialize._onAddSerializable = null;
        Serialize._serializedMap = null;

    }

    public static function loadFromData(model:Model, data:String, hotReload:Bool = false):Bool {

        if (data == null) {
            // No data, stop here
            return false;
        }

        // Serialize previous data to compare it with new one
        Serialize._serializedMap = new Map();
        Serialize._deserializedMap = new Map();
        Serialize._deserializedCacheMap = null;

        Serialize.serializeValue(model);

        var prevDeserializedMap:Map<String, Serializable> = Serialize._deserializedMap;
        Serialize._serializedMap = null;
        Serialize._deserializedMap = null;
        Serialize._deserializedCacheMap = null;

        // Decode new data
        var decoded = Utils.decodeChangesetData(data);

        // Then deserialize it
        Serialize._serializedMap = decoded.serializedMap;
        Serialize._deserializedMap = new Map();
        Serialize._deserializedCacheMap = hotReload ? prevDeserializedMap : null;
        Serialize._createdInstances = [];

        Serialize.deserializeValue(decoded.serialized, model);

        var deserializedMap:Map<String, Serializable> = Serialize._deserializedMap;

        final createdInstances = Serialize._createdInstances;
        Serialize._createdInstances = null;

        for (i in 0...createdInstances.length) {
            final instance = createdInstances[i];
            final autorunMarked = Reflect.field(instance, '_autorunMarkedMethods');
            if (autorunMarked != null) {
                Reflect.callMethod(
                    instance,
                    autorunMarked,
                    []
                );
            }
        }

        Serialize._deserializedMap = null;
        Serialize._serializedMap = null;
        Serialize._deserializedCacheMap = null;

        // Serialize new data to compare it with prev one
        Serialize._serializedMap = new Map();
        Serialize._deserializedMap = new Map();
        Serialize._deserializedCacheMap = null;

        Serialize.serializeValue(model);

        var newDeserializedMap:Map<String, Serializable> = Serialize._deserializedMap;
        Serialize._serializedMap = null;
        Serialize._deserializedMap = null;
        Serialize._deserializedCacheMap = null;

        // Destroy previous model objects not used anymore (if any)
        // Use previous serialized map to detect unused models
        for (k => item in prevDeserializedMap) {
            if (newDeserializedMap.get(k) != item) {
                if (Std.isOfType(item, Model)) {
                    var _model:Model = cast item;
                    if (_model != model) {
                        if (@:privateAccess _model.serializeShouldDestroy()) {
                            _model.destroy();
                        }
                    }
                }
            }
        }

        return true;

    }

}
