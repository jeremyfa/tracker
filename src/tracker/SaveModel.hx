package tracker;

import tracker.Tracker.backend;

class SaveModel {

    static var BACKUP_NUM_STEPS:Int = 20000;

    static var NUM_BACKUPS:Int = 4;

    static var BACKUP_STEPS:Array<Int> = null;

    static var backupStepByKey:Map<String,Int> = null;

    static var busyKeys:Array<String> = [];

/// Public API

    public static function getSavedOrCreate<T:Model>(modelClass:Class<T>, key:String, ?args:Array<Dynamic>):T {

        // Create new instance
        var instance = Type.createInstance(modelClass, args != null ? args : []);

        // Load saved data
        loadFromKey(instance, key);

        return instance;

    }

    /** Load data from the given key. */
    public static function loadFromKey(model:Model, key:String):Bool {

        if (busyKeys.indexOf(key) != -1) {
            throw 'Cannot load data from key $key because some work is being done on it';
        }

        initBackupLogicIfNeeded(key);

        var rawId = backend.readString('save_id_1_' + key);
        var id = rawId != null ? Std.parseInt(rawId) : -1;
        if (id != 1 && id != 2) {
            rawId = backend.readString('save_id_2_' + key);
            id = rawId != null ? Std.parseInt(rawId) : -1;
        }

        var data:String = null;

        if (id != 1 && id != 2) {
            backend.warning('Failed to load save from key: $key (no existing save?)');
        }
        else {
            data = backend.readString('save_data_' + id + '_' + key);
            if (data == null) {
                backend.warning('Failed to load save from key: $key/$id (corrupted save, try backups?)');
            }
        }

        if (data == null) {
            data = fetchMostRecentBackup(key);
            if (data == null) {
                backend.warning('No backup available for key $key, that is probably a new save slot.');
            }
            else {
                backend.success('Recovered from backup!');
            }
        }

        return SerializeModel.loadFromData(model, data);

    }
    public static function autoSaveAsKey(model:Model, key:String, appendInterval:Float = 1.0, compactInterval:Float = 60.0) {

        // Init backup logic if needed
        initBackupLogicIfNeeded(key);

        var serializer = model.serializer;
        if (serializer == null) {
            serializer = new SerializeModel();
            serializer.checkInterval = appendInterval;
            serializer.compactInterval = compactInterval;
        }
        else if (serializer.checkInterval != appendInterval || serializer.compactInterval != compactInterval) {
            backend.warning('A serializer is already assigned with different appendInterval and compactInterval');
        }

        var saveDataKey1 = 'save_data_1_' + key;
        var saveDataKey2 = 'save_data_2_' + key;
        var saveIdKey1 = 'save_id_1_' + key;
        var saveIdKey2 = 'save_id_2_' + key;

        // Start listening for changes to save them
        serializer.onChangeset(model, function(changeset) {

            // Mark this key as busy
            busyKeys.push(key);

            if (changeset.append) {

                // Append
                //
                #if tracker_debug_save
                trace('Save $key (append ${changeset.data.length})');//: ' + changeset.data);
                #end

                (function(data:String, key:String) {
                    backend.runInBackground(function() {

                        // We use and update multiple files to ensure that, in case of crash or any other issue
                        // when writing a file, it will fall back to the other one safely. If anything goes
                        // wrong, there should always be a save file to fall back on.
                        
                        // Append first file
                        backend.appendString(saveDataKey1, Utils.encodeChangesetData(data));
                        // Mark this first file as the valid one on first id key
                        backend.saveString(saveIdKey1, '1');
                        // Mark this first file as the valid one on second id key
                        backend.saveString(saveIdKey2, '1');

                        // Append second file
                        backend.appendString(saveDataKey2, Utils.encodeChangesetData(data));
                        // Mark this second file as the valid one on first id key
                        backend.saveString(saveIdKey1, '2');
                        // Mark this second file as the valid one on second id key
                        backend.saveString(saveIdKey2, '2');

                        backend.runInMain(function() {
                            // Pop busy key
                            var busyIndex = busyKeys.indexOf(key);
                            if (busyIndex != -1) {
                                busyKeys.splice(busyIndex, 1);
                            }
                            else {
                                backend.error('Failed to remove busy key: $key (none in list)');
                            }
                        });

                    });
                })(changeset.data, key);

            } else {

                // Compact
                //
                #if tracker_debug_save
                trace('Save $key (full ${changeset.data.length})');//: ' + changeset.data);
                #end

                var backupStep = backupStepByKey.get(key);
                var backupId = BACKUP_STEPS[backupStep];
                
                (function(data:String, key:String, backupStep:Int, backupId:Int) {
                    backend.runInBackground(function() {

                        // We use and update multiple files to ensure that, in case of crash or any other issue
                        // when writing a file, it will fall back to the other one safely. If anything goes
                        // wrong, there should always be a save file to fall back on.

                        // Save first file
                        backend.saveString(saveDataKey1, Utils.encodeChangesetData(data));
                        // Mark this first file as the valid one on first id key
                        backend.saveString(saveIdKey1, '1');
                        // Mark this first file as the valid one on second id key
                        backend.saveString(saveIdKey2, '1');

                        // Save second file
                        backend.saveString(saveDataKey2, Utils.encodeChangesetData(data));
                        // Mark this second file as the valid one on first id key
                        backend.saveString(saveIdKey1, '2');
                        // Mark this second file as the valid one on second id key
                        backend.saveString(saveIdKey2, '2');

                        // Save a backup on compact
                        // That file will be used at load if we fail to load the regular one
                        backend.saveString('backup_data_' + backupId + '_' + key, Math.round(Date.now().getTime()) + ':' + data.length + ':' + data);

                        // Increment backup step
                        backupStep = (backupStep + 1) % BACKUP_NUM_STEPS;

                        // Update backup step on disk
                        backend.saveString('backup_step_1_' + key, '' + backupStep);
                        backend.saveString('backup_step_2_' + key, '' + backupStep);

                        backend.runInMain(function() {

                            // Update backup step in map
                            backupStepByKey.set(key, backupStep);

                            // Pop busy key
                            var busyIndex = busyKeys.indexOf(key);
                            if (busyIndex != -1) {
                                busyKeys.splice(busyIndex, 1);
                            }
                            else {
                                backend.error('Failed to remove busy key: $key (none in list)');
                            }
                        });
                        

                    });
                })(changeset.data, key, backupStep, backupId);
            }

        });

        // Assign component
        if (model.serializer != serializer) {
            model.serializer = serializer;

            #if !tracker_ceramic
            @:privateAccess serializer.entity = model;
            @:privateAccess serializer.bindAsComponent();
            model.onDestroy(serializer, _ -> {
                serializer.destroy();
                serializer = null;
            });
            #end
        }

    }

    static function initBackupLogicIfNeeded(key:String):Void {

        if (backupStepByKey == null) {
            backupStepByKey = new Map();

            BACKUP_STEPS = Utils.uniformFrequencyList(
                [1, 2, 3, 4],
                [
                    0.5 - 20.0 / BACKUP_NUM_STEPS - 2.0 / BACKUP_NUM_STEPS,
                    0.5 - 20.0 / BACKUP_NUM_STEPS - 2.0 / BACKUP_NUM_STEPS,
                    20.0 / BACKUP_NUM_STEPS,
                    2.0 / BACKUP_NUM_STEPS
                ],
                BACKUP_NUM_STEPS
            );
        }
        
        if (!backupStepByKey.exists(key)) {

            var rawStep = backend.readString('backup_step_1_' + key);
            var step = rawStep != null ? Std.parseInt(rawStep) : -1;
            if (step == null || Math.isNaN(step) || step < 0 || step >= BACKUP_NUM_STEPS) {
                rawStep = backend.readString('backup_step_2_' + key);
                step = rawStep != null ? Std.parseInt(rawStep) : -1;
            }

            if (step == null || Math.isNaN(step) || step < 0 || step >= BACKUP_NUM_STEPS) {
                backend.warning('No backup step saved, start with zero');
                step = 0;
            }

            backupStepByKey.set(key, step);
        }

    }

    static function fetchMostRecentBackup(key:String):String {

        var backups:Array<String> = [];
        var times:Array<Float> = []; 

        for (backupId in 0...4) {
            var backup = backend.readString('backup_data_' + backupId + '_' + key);

            if (backup != null) {
                // Extract time and data
                var colonIndex = backup.indexOf(':');
                if (colonIndex != -1) {
                    var rawTime = backup.substring(0, colonIndex);
                    var time:Null<Float> = Std.parseFloat(rawTime);
                    if (time != null && !Math.isNaN(time) && time > 0) {
                        backups.push(backup.substring(colonIndex + 1));
                        times.push(time);
                    }
                }
            } 
        }

        var bestTime:Float = -1;
        var bestIndex:Int = -1;

        // Find most rencent backup among every loaded backup
        for (i in 0...times.length) {
            var time = times[i];
            if (time > bestTime) {
                bestTime = time;
                bestIndex = i;
            }
        }

        if (bestIndex != -1) {
            // Found one!
            return backups[bestIndex];
        }
        else {
            // No backup available
            return null;
        }

    }

}
