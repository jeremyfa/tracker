package tracker;

import haxe.Json;
import tracker.Equal;
import tracker.ShareItem;
import tracker.Tracker.backend;

class ShareModel extends #if tracker_ceramic ceramic.Entity #else Entity #end implements #if tracker_ceramic ceramic.Component #else tracker.Component #end {

/// Events

    /** Triggered when there is new data to be shared */
    @event function changeset(changeset:ShareChangeset);

/// Properties

    public var serializedMap(default,null):Map<String,{ id:String, type:String, props:Dynamic }> = new Map();

    var deserializedMap(default,null):Map<String,Serializable> = new Map();

    var destroysToDispatch:Array<String> = null;

    public var model(get,null):Model;
    inline function get_model():Model return entity;

    var entity:Model;

    #if tracker_ceramic

    var lastCheckedFrame:Int = -1;

    #end

/// Settings

    public var destroyModelOnUntrack:Bool = true;

    public var checkInterval:Float = 0.1;

/// Lifecycle

    function bindAsComponent() {

        if (checkInterval > 0) {
            // Synchronize with real data at regular interval
            backend.interval(this, checkInterval, synchronizeIfNeeded);
        }

        // Track root model
        track(model);

        // Share all
        shareAll();

    }

/// Internal

    var trackedModels:Map<String,Model> = new Map();

    var willCleanDestroyedTrackedModels:Bool = false;

    var dirtyModels:Map<String,Model> = new Map();

    var dirty:Bool = true;

    inline function track(model:Model) {

        if (!model.destroyed && !trackedModels.exists(model._serializeId)) {
            trackedModels.set(model._serializeId, model);
            deserializedMap.set(model._serializeId, model);
            model.onModelDirty(this, explicitModelDirty);
            model.onObservedDirty(this, modelDirty);
            model.onceDestroy(this, trackedModelDestroyed);
        }

    }

    inline function untrack(model:Model) {

        if (trackedModels.exists(model._serializeId)) {
            trackedModels.remove(model._serializeId);
            deserializedMap.remove(model._serializeId);
            model.offModelDirty(explicitModelDirty);
            model.offObservedDirty(modelDirty);
            model.offDestroy(trackedModelDestroyed);
            if (destroyModelOnUntrack) {
                model.destroy();
            }
        }

    }

    public function encodeValue(value:Any):Any {
        return Json.stringify(value);
    }

    public function decodeValue(encoded:Any):Any {
        return Json.parse(encoded);
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
                    if (destroysToDispatch == null) {
                        destroysToDispatch = [];
                    }
                    if (!destroysToDispatch.contains(model._serializeId)) {
                        destroysToDispatch.push(model._serializeId);
                    }
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

    function synchronizeIfNeeded() {

        #if tracker_ceramic
        final currentFrame = ceramic.App.app.frame;
        if (lastCheckedFrame == currentFrame) {
            return;
        }
        lastCheckedFrame = currentFrame;
        #end

        synchronize();

    }

    /** Synchronize (expected to be called at regular intervals or when something important needs to be serialized) */
    public function synchronize() {

        if (!dirty) return;
        dirty = false;

        var shareItems:Array<ShareItem> = [];

        if (destroysToDispatch != null) {
            while (destroysToDispatch.length > 0) {
                shareItems.push({
                    id: destroysToDispatch.shift(),
                    action: DESTROY
                });
            }
        }

        for (id in dirtyModels.keys()) {
            var model = dirtyModels.get(id);
            if (!model.destroyed && trackedModels.exists(model._serializeId)) {
                model.dirty = false;
                serializeModel(model, shareItems);
            }
        }
        dirtyModels = new Map();

        if (shareItems.length > 0) {
            emitChangeset({ items: shareItems });
        }

    }

    /** Recompute the whole object tree. This will untrack every object not on the model anymore
        and generate a new changeset with the whole serialized object tree. */
    public function shareAll(skipUnchanged:Bool = false, ?done:(Array<ShareItem>)->Void):Void {

        var prevSerializedMap = serializedMap;
        var shareItems:Array<ShareItem> = [];

        Serialize._serializedMap = new Map();

        if (skipUnchanged) {
            Serialize._onAddSerializable = function(serializable:Serializable) {

                if (Std.isOfType(serializable, Model)) {
                    var model:Model = cast serializable;
                    model.observedDirty = false;
                    track(model);

                    var prevSerialized = prevSerializedMap.get(model._serializeId);
                    var serialized = Serialize._serializedMap.get(model._serializeId);

                    final serializedProps:Dynamic = serialized.props;

                    var itemProps:Dynamic = {};
                    var shouldSendItem = false;
                    var action:ShareItemAction = SET;

                    // This is the dirty model that already existed,
                    // check if fields have changed
                    if (prevSerialized != null && prevSerialized.props != null) {
                        action = UPDATE;
                        final prevProps = prevSerialized.props;
                        for (field in Reflect.fields(serializedProps)) {
                            if (!Equal.equal(
                                Reflect.field(serializedProps, field),
                                Reflect.field(prevProps, field)
                            )) {
                                // Value changed, add this field
                                shouldSendItem = true;
                                Reflect.setField(itemProps, field, encodeValue(Reflect.field(serializedProps, field)));
                            }
                        }
                    }
                    else {
                        shouldSendItem = true;
                        // In other situations, they are simply new models, so we add the field anyway
                        for (field in Reflect.fields(serializedProps)) {
                            Reflect.setField(itemProps, field, encodeValue(Reflect.field(serializedProps, field)));
                        }
                    }

                    if (shouldSendItem) {
                        final item:ShareItem = {
                            id: serialized.id,
                            action: action,
                            type: serialized.type,
                            props: itemProps
                        };
                        shareItems.push(item);
                    }
                }

            };
        }
        else {
            Serialize._onAddSerializable = function(serializable:Serializable) {

                if (Std.isOfType(serializable, Model)) {
                    var model:Model = cast serializable;
                    model.observedDirty = false;
                    track(model);

                    var itemProps:Dynamic = {};

                    var serialized = Serialize._serializedMap.get(model._serializeId);
                    final serializedProps:Dynamic = serialized.props;

                    for (field in Reflect.fields(serializedProps)) {
                        Reflect.setField(itemProps, field, encodeValue(Reflect.field(serializedProps, field)));
                    }

                    final item:ShareItem = {
                        id: serialized.id,
                        action: SET,
                        type: serialized.type,
                        props: itemProps
                    };

                    shareItems.push(item);
                }

            };
        }

        var serialized = Serialize.serializeValue(model);

        serializedMap = Serialize._serializedMap;

        Serialize._onAddSerializable = null;
        Serialize._serializedMap = null;

        cleanTrackingFromPrevSerializedMap(prevSerializedMap);

        backend.onceImmediate(function() {

            // Check if there are destroyed models
            if (destroysToDispatch != null) {
                while (destroysToDispatch.length > 0) {
                    shareItems.push({
                        id: destroysToDispatch.shift(),
                        action: DESTROY
                    });
                }
            }

            // Emit changeset
            if (shareItems.length > 0) {
                emitChangeset({ items: shareItems });
            }
        });

        // Call done() callback if provided
        if (done != null) done(data);

    }

    public function receiveShared(changeset:ShareChangeset) {

        Serialize._serializedMap = serializedMap;
        Serialize._deserializedMap = deserializedMap;

        try {
            for (item in changeset.items) {
                switch item.action {

                    case SET | UPDATE:
                        // Update serialized data
                        var serializedData = serializedMap.get(item.id);
                        if (serializedData == null) {
                            serializedData = {
                                id: item.id,
                                type: item.type,
                                props: {}
                            };
                        }
                        if (item.props != null) {
                            for (field in Reflect.fields(item.props)) {
                                Reflect.setField(
                                    serializedData.props,
                                    field,
                                    decodeValue(Reflect.field(item.props, field))
                                );
                            }
                        }

                    case DESTROY:
                }
            }

            for (item in changeset.items) {
                switch item.action {

                    case SET:
                        var serializable = deserializedMap.get(item.id);
                        var serializedData = serializedMap.get(item.id);
                        Serialize.deserializeValue(
                            serializedData,
                            serializable, true
                        );

                    case UPDATE:
                        var serializable = deserializedMap.get(item.id);
                        var serializedData = serializedMap.get(item.id);
                        var changedProps:Dynamic = {};
                        if (item.props != null) {
                            for (field in Reflect.fields(item.props)) {
                                Reflect.setField(changedProps, field, Reflect.field(serializedData, field));
                            }
                        }
                        Serialize.deserializeValue({
                                id: item.id,
                                type: serializedData.type,
                                props: changedProps
                            },
                            serializable, true
                        );

                    case DESTROY:
                        var serializable = deserializedMap.get(item.id);
                        if (serializable is Model) {
                            var model:Model = cast serializable;
                            if (model != null) {
                                model.destroy();
                            }
                            else {
                                backend.warning('Trying to destroy item ${item.id}, but item was not found!');
                            }
                        }
                }
            }
        }
        catch (e:Dynamic) {
            backend.error('Failed to receive shared data: ' + e);
        }

        Serialize._serializedMap = null;
        Serialize._deserializedMap = null;

    }

    inline function serializeModel(model:Model, shareItems:Array<ShareItem>) {

        // Keep previous version of serialized model
        final serializeId = model._serializeId;
        final prevSerialized = serializedMap.get(serializeId);

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

                var serialized = Serialize._serializedMap.get(model._serializeId);

                final serializedProps:Dynamic = serialized.props;

                var itemProps:Dynamic = {};
                var shouldSendItem = false;
                var action:ShareItemAction = SET;

                // This is the dirty model that already existed,
                // check if fields have changed
                if (model._serializeId == serializeId && prevSerialized != null && prevSerialized.props != null) {
                    action = UPDATE;
                    final prevProps = prevSerialized.props;
                    for (field in Reflect.fields(serializedProps)) {
                        if (!Equal.equal(
                            Reflect.field(serializedProps, field),
                            Reflect.field(prevProps, field)
                        )) {
                            // Value changed, add this field
                            shouldSendItem = true;
                            Reflect.setField(itemProps, field, encodeValue(Reflect.field(serializedProps, field)));
                        }
                    }
                }
                else {
                    shouldSendItem = true;
                    // In other situations, they are simply new models, so we add the field anyway
                    for (field in Reflect.fields(serializedProps)) {
                        Reflect.setField(itemProps, field, encodeValue(Reflect.field(serializedProps, field)));
                    }
                }

                if (shouldSendItem) {
                    final item:ShareItem = {
                        id: serialized.id,
                        action: action,
                        type: serialized.type,
                        props: itemProps
                    };
                    shareItems.push(item);
                }

                track(model);
            }

        };

        Serialize.serializeValue(model);

        Serialize._onCheckSerializable = null;
        Serialize._onAddSerializable = null;
        Serialize._serializedMap = null;

    }

/// Public (extension) API

    public static function autoShare(model:Model, checkInterval:Float = 0.032, #if tracker_ceramic ?owner:ceramic.Entity #else ?owner:Entity #end , onChangeset:(changeset:ShareChangeset)->Void):ShareModel {

        // If there is already a sharer, just use that
        var sharer = model.sharer;
        if (sharer != null) {
            if (sharer.checkInterval != checkInterval) {
                backend.warning('A sharer is already assigned with different checkInterval');
            }
            sharer.onChangeset(owner, onChangeset);
            sharer.shareAll();
        }
        else {
            // Create sharer
            sharer = new ShareModel();
            sharer.checkInterval = checkInterval;
            sharer.onChangeset(owner, onChangeset);
            model.sharer = sharer;

            #if !tracker_ceramic
            @:privateAccess sharer.entity = model;
            @:privateAccess sharer.bindAsComponent();
            model.onDestroy(sharer, _ -> {
                sharer.destroy();
                sharer = null;
            });
            #end
        }

        return sharer;

    }

}
